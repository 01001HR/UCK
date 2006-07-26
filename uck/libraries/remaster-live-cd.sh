#!/bin/bash

###################################################################################
# UCK - Ubuntu Customization Kit                                                  #
# Copyright (C) 2006  UCK Team                                                    #
#                                                                                 #
# This program is free software; you can redistribute it and/or                   #
# modify it under the terms of the GNU General Public License                     #
# as published by the Free Software Foundation; either version 2                  #
# of the License.                                                                 #
#                                                                                 #
# This program is distributed in the hope that it will be useful,                 #
# but WITHOUT ANY WARRANTY; without even the implied warranty of                  #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                   #
# GNU General Public License for more details.                                    #
#                                                                                 #
# You should have received a copy of the GNU General Public License               #
# along with this program; if not, write to the Free Software                     #
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. #
###################################################################################

function usage()
{
	echo "Usage: $0 path-to-iso-file.iso customization-dir/"
}

function failure()
{
	echo "$@"
	exit 2
}

function remove_directory()
{
	DIR_TO_REMOVE="$1"
	if [ "$DIR_TO_REMOVE" = "/" ]; then
		failure "Trying to remove root directory"
	fi
	rm -rf "$DIR_TO_REMOVE"
}

function unpack_initrd()
{
	if [ -e  "$INITRD_REMASTER_DIR" ]; then
		remove_directory "$INITRD_REMASTER_DIR" || failure "Cannot remove $INITRD_REMASTER_DIR"
	fi
	mkdir -p "$INITRD_REMASTER_DIR" || failure "Cannot create directory $INITRD_REMASTER_DIR"

	pushd "$INITRD_REMASTER_DIR" || failure "Failed to change directory to $INITRD_REMASTER_DIR, error=$?"
	cat "$ISO_REMASTER_DIR/casper/initrd.gz" | gzip -d | cpio -i
	RESULT=$?

	if [ $RESULT -ne 0 ]; then
		failure "Failed to unpack $ISO_REMASTER_DIR/casper/initrd.gz to $INITRD_REMASTER_DIR, error=$RESULT"
	fi

	popd
}

function pack_initrd()
{
	pushd "$INITRD_REMASTER_DIR" || failure "Failed to change directory to $INITRD_REMASTER_DIR, error=$?"
	find | cpio -H newc -o | gzip >"$NEW_FILES_DIR/initrd.gz"
	RESULT=$?
	if [ $RESULT -ne 0 ]; then
		failure "Failed to compress initird image $INITRD_REMASTER_DIR to $NEW_FILES_DIR/initrd.gz, error=$RESULT"
	fi
	popd

	if [ -e "$ISO_REMASTER_DIR/casper/initrd.gz" ]; then
		rm -f "$ISO_REMASTER_DIR/casper/initrd.gz" || failure "Failed to remove $ISO_REMASTER_DIR/casper/initrd.gz, error=$?"
	fi

	mv "$NEW_FILES_DIR/initrd.gz" "$ISO_REMASTER_DIR/casper/initrd.gz" || failure "Failed to copy $NEW_FILES_DIR/initrd.gz to $ISO_REMASTER_DIR/casper/initrd.gz, error=$?"
}

function customize_initrd()
{
	echo "Running initrd customization script $CUSTOMIZE_DIR/customize_initrd, initrd remaster dir is $INITRD_REMASTER_DIR"
	export INITRD_REMASTER_DIR
	. $CUSTOMIZE_DIR/customize_initrd || failure "Running initird customization script $CUSTOMIZE_DIR/customize_initrd with remaster dir $INITRD_REMASTER_DIR failed, error=$?"
	export -n INITRD_REMASTER_DIR
}

function customize_iso()
{
	echo "Running ISO customization script $CUSTOMIZE_DIR/customize_iso, iso remaster dir is $ISO_REMASTER_DIR"
	export ISO_REMASTER_DIR
	export CUSTOMIZE_DIR
	"$CUSTOMIZE_DIR/customize_iso" || failure "Running ISO customization script $CUSTOMIZE_DIR/customize_iso with remaster dir $ISO_REMASTER_DIR failed, error=$?"
	export -n ISO_REMASTER_DIR
	export -n CUSTOMIZE_DIR
}

function mount_iso()
{
	echo "Mounting ISO image..."
	mkdir -p "$ISO_MOUNT_DIR" || failure "Cannot create directory $ISO_MOUNT_DIR, error=$?"
	mount "$ISO_IMAGE" "$ISO_MOUNT_DIR" -o loop || failure "Cannot mount $ISO_IMAGE in $ISO_MOUNT_DIR, error=$?"
}

function unmount_iso()
{
	if [ -e "$ISO_MOUNT_DIR" ] ; then
		umount "$ISO_MOUNT_DIR" || echo "Failed to unmount ISO mount directory $ISO_MOUNT_DIR, error=$?"
		rmdir "$ISO_MOUNT_DIR" || echo "Failed to remove ISO mount directory $ISO_MOUNT_DIR, error=$?"
	fi
}

function unpack_iso()
{
	remove_iso_remaster_dir
	cp -a "$ISO_MOUNT_DIR" "$ISO_REMASTER_DIR" || failure "Failed to unpack ISO from $ISO_MOUNT_DIR to $ISO_REMASTER_DIR"
}

function unpack_rootfs()
{
	echo "Mounting SquashFS image..."

	mkdir -p "$SQUASHFS_MOUNT_DIR" || failure "Cannot create directory $SQUASHFS_MOUNT_DIR, error=$?"
	mount -t squashfs "$SQUASHFS_IMAGE" "$SQUASHFS_MOUNT_DIR" -o loop || failure "Cannot mount $SQUASHFS_IMAGE in $SQUASHFS_MOUNT_DIR, error=$?"

	if [ -e "$REMASTER_DIR" ]; then
		remove_directory "$REMASTER_DIR" || failure "Failed to remove directory $REMASTER_DIR, error=$?"
	fi

	echo "Copying data to remastering root directory..."
	cp -a "$SQUASHFS_MOUNT_DIR" "$REMASTER_DIR" || failure "Cannot copy files from $SQUASHFS_MOUNT_DIR to $REMASTER_DIR, error=$?"

	umount "$SQUASHFS_MOUNT_DIR" || echo "Failed to unmount SQUASHFS mount directory $SQUASHFS_MOUNT_DIR, error=$?"
	rmdir "$SQUASHFS_MOUNT_DIR" || echo "Failed to remove SQUASHFS mount directory $SQUASHFS_MOUNT_DIR, error=$?"

	if [ "$KEEP_PREVIOUS_REMASTER_DIR" = "no" ] ; then
		mount -t proc proc "$REMASTER_DIR/proc" || echo "Failed to unmount $REMASTER_DIR/proc, error=$?"
		mount -t sysfs sysfs "$REMASTER_DIR/sys" || echo "Failed to unmount $REMASTER_DIR/sys, error=$?"
	fi
}

function prepare_rootfs_for_net_update()
{
	echo "Copying resolv.conf"
	cp -f /etc/resolv.conf "$REMASTER_DIR/etc/resolv.conf" || failure "Failed to copy resolv.conf to image directory, error=$?"

	echo "Copying local apt cache, if available"
	if [ -e "$APT_CACHE_SAVE_DIR" ]; then
		mv "$REMASTER_DIR/var/cache/apt/" "$REMASTER_DIR/var/cache/apt.original" || failure "Cannot move $REMASTER_DIR/var/cache/apt/ to $REMASTER_DIR/var/cache/apt.original, error=$?"
		mv "$APT_CACHE_SAVE_DIR" "$REMASTER_DIR/var/cache/apt" || failure "Cannot copy apt cache dir $APT_CACHE_SAVE_DIR to $REMASTER_DIR/var/cache/apt/, error=$?"
	else
		cp -a "$REMASTER_DIR/var/cache/apt/" "$REMASTER_DIR/var/cache/apt.original" || failure "Cannot copy $REMASTER_DIR/var/cache/apt/ to $REMASTER_DIR/var/cache/apt.original, error=$?"
	fi
}

function run_rootfs_chroot_customization()
{
	echo "Copying customization files..."
	cp -a "$CUSTOMIZE_DIR" "$REMASTER_CUSTOMIZE_DIR" || failure "Cannot copy files from $CUSTOMIZE_DIR to $REMASTER_CUSTOMIZE_DIR, error=$?"

	echo "Running customization script..."
	chroot "$REMASTER_DIR" "/$CUSTOMIZATION_SCRIPT" || failure "Running customization script failed, error=$?"
	echo "Customization script finished"
}

function save_apt_cache()
{
	echo "Saving apt cache"
	if [ -e "$APT_CACHE_SAVE_DIR" ]; then
		mv -f "$APT_CACHE_SAVE_DIR" "$APT_CACHE_SAVE_DIR.old" || failure "Cannot save old apt-cache $APT_CACHE_SAVE_DIR to $APT_CACHE_SAVE_DIR.old, error=$?"
	fi
	mv "$REMASTER_DIR/var/cache/apt/" "$APT_CACHE_SAVE_DIR" || failure "Cannot move current apt-cache $REMASTER_DIR/var/cache/apt/ to $APT_CACHE_SAVE_DIR, error=$?"
	mv "$REMASTER_DIR/var/cache/apt.original" "$REMASTER_DIR/var/cache/apt" || failure "Cannot restore original apt-cache $REMASTER_DIR/var/cache/apt.original to $REMASTER_DIR/var/cache/apt, error=$?"
}

function clean_rootfs()
{
	echo "Cleaning up apt"
	chroot "$REMASTER_DIR" apt-get clean || failure "Failed to run apt-get clean, error=$?"

	echo "Removing customize dir"
	#Run in chroot to be on safe side
	chroot "$REMASTER_DIR" rm -rf "$REMASTER_CUSTOMIZE_RELATIVE_DIR" || failure "Cannot remove customize dir $REMASTER_CUSTOMIZE_RELATIVE_DIR, error=$?"

	echo "Cleaning up temporary directories"
	#Run in chroot to be on safe side
	chroot "$REMASTER_DIR" 'rm -rf /tmp/* /tmp/.* /var/tmp/* /var/tmp/.*' || echo "Warning: Cannot remove temoporary files, error=$?. Ignoring"

	#mv -f "$RESOLV_CONF_BACKUP" "$REMASTER_DIR/etc/resolv.conf" || failure "Failed to restore resolv.conf, error=$?"
	rm -f "$REMASTER_DIR/etc/resolv.conf" || failure "Failed to remove resolv.conf, error=$?"

	umount "$REMASTER_DIR/proc"
	umount "$REMASTER_DIR/sys"
}

function prepare_new_files_directories()
{
	echo "Preparing directory for new files"
	if [ -e "$NEW_FILES_DIR" ]; then
		remove_directory "$NEW_FILES_DIR" || failure "Failed to remove directory $NEW_FILES_DIR"
	fi
	mkdir -p "$NEW_FILES_DIR"
}

function pack_rootfs()
{
	echo "Updating files lists"
	chroot "$REMASTER_DIR" dpkg-query -W --showformat='${Package} ${Version}\n' > "$ISO_REMASTER_DIR/casper/filesystem.manifest" || failure "Cannot update filesystem.manifest, error=$?"
	cp "$ISO_REMASTER_DIR/casper/filesystem.manifest" "$ISO_REMASTER_DIR/casper/filesystem.manifest-desktop" || failure "Failed to copy $ISO_REMASTER_DIR/casper/filesystem.manifest to $ISO_REMASTER_DIR/casper/filesystem.manifest-desktop"

	echo "Preparing SquashFS image"
	if [ -e "$ISO_REMASTER_DIR/casper/filesystem.squashfs" ]; then
		rm -f "$ISO_REMASTER_DIR/casper/filesystem.squashfs" || failure "Cannot remove $ISO_REMASTER_DIR/casper/filesystem.squashfs to make room for created squashfs image, error=$?"
	fi

	EXTRA_OPTS=""

	if [ -e "$CUSTOMIZE_DIR/rootfs.sort" ] ; then
		#FIXME: space not allowed in $CUSTOMIZE_DIR
		EXTRA_OPTS="-sort $CUSTOMIZE_DIR/rootfs.sort"
	fi

	mksquashfs "$REMASTER_DIR" "$ISO_REMASTER_DIR/casper/filesystem.squashfs" $EXTRA_OPTS || failure "Failed to create squashfs image to $ISO_REMASTER_DIR/casper/filesystem.squashfs, error=$?"
}

function remove_iso_remaster_dir()
{
	if [ -e "$ISO_REMASTER_DIR" ] ; then
		echo "Removing ISO remastering dir"
		remove_directory "$ISO_REMASTER_DIR" || failure "Failed to remove directory $ISO_REMASTER_DIR, error=$?"
	fi
}

function remove_remaster_dir()
{
	echo "Removing remastering root dir"
	remove_directory "$REMASTER_DIR"
}

function remove_remaster_initrd()
{
	echo "Removing remastering root dir"
	remove_directory "$INITRD_REMASTER_DIR"
}

function update_iso_locale()
{
	echo "Updating locale"

	if [ -e "$CUSTOMIZE_DIR/livecd_locale" ]; then
		LIVECD_LOCALE=`cat "$CUSTOMIZE_DIR/livecd_locale"`
		cat "$ISO_REMASTER_DIR/isolinux/isolinux.cfg" | sed "s#\<append\>#append debian-installer/locale=$LIVECD_LOCALE#g" >"$NEW_FILES_DIR/isolinux.cfg"
		RESULT=$?
		if [ $RESULT -ne 0 ]; then
			failure "Failed to filter $ISO_REMASTER_DIR/isolinux/isolinux.cfg into $NEW_FILES_DIR/isolinux.cfg, error=$RESULT"
		fi

		cp -a "$NEW_FILES_DIR/isolinux.cfg" "$ISO_REMASTER_DIR/isolinux/isolinux.cfg" || failure "Failed to copy $NEW_FILES_DIR/isolinux.cfg to $ISO_REMASTER_DIR/isolinux/isolinux.cfg, error=$?"
	fi
}

function pack_isofs()
{
	echo "Updating md5sums"
	pushd "$ISO_REMASTER_DIR"
	find . -type f -print0 | xargs -0 md5sum > md5sum.txt
	popd

	echo "Creating ISO image"

	LIVECD_ISO_DESCRIPTION="Remastered Ubuntu LiveCD"

	if [ -e "$CUSTOMIZE_DIR/iso_description" ] ; then
		LIVECD_ISO_DESCRIPTION=`cat "$CUSTOMIZE_DIR/iso_description"`
	fi

	echo "ISO description set to: $LIVECD_ISO_DESCRIPTION"

	MKISOFS_EXTRA_OPTIONS=""
	if [ -e "$CUSTOMIZE_DIR/mkisofs_extra_options" ] ; then
		MKISOFS_EXTRA_OPTIONS=`cat "$CUSTOMIZE_DIR/mkisofs_extra_options"`
	fi

	mkisofs -o "$NEW_FILES_DIR/livecd.iso" \
		-b "isolinux/isolinux.bin" -c "isolinux/boot.cat" \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		-V "$LIVECD_ISO_DESCRIPTION" -cache-inodes -r -J -l \
		$MKISOFS_EXTRA_OPTIONS \
		"$ISO_REMASTER_DIR"

	RESULT=$?
	if [ $RESULT -ne 0 ]; then
		failure "Failed to create ISO image, error=$RESULT"
	fi

	echo "Generating md5sum for newly created ISO..."
	cd $NEW_FILES_DIR
	md5sum livecd.iso > livecd.iso.md5
}