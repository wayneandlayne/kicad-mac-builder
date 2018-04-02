#!/bin/bash

set -e

crash_cleanup() {
    hdiutil detach $MOUNTPOINT || true
    hdiutil detach /Volumes/"${MOUNT_NAME}" || true
}
trap crash_cleanup EXIT

setup_dmg()
{
    # make the mountpoint
    if [ -e $MOUNTPOINT ]; then
        # it might be a leftover mount from a crashed previous run, so try to unmount it before removing it.
        diskutil unmount $MOUNTPOINT || true
        rm -r $MOUNTPOINT
    fi
    mkdir -p $MOUNTPOINT
    
    # untar the template
    if [ -e $TEMPLATE ]; then
        rm $TEMPLATE
    fi
    tar xf $PACKAGING_DIR/$TEMPLATE.tar.bz2
    if [ ! -e $TEMPLATE ]; then
        echo "Unable to find $TEMPLATE"
        exit 1
    fi
    
    # resize the template, and mount it
    if ! hdiutil resize -size $DMG_SIZE $TEMPLATE; then
        echo "If hdituil failed to resize, saying the size is above a maximum, reboot.  If you know the root cause or a better way to fix this, please let us know."
        exit 1
    fi
    hdiutil attach $TEMPLATE -noautoopen -mountpoint $MOUNTPOINT
}


fixup_and_cleanup()
{
    # update background of the DMG
    cp $PACKAGING_DIR/background.png $MOUNTPOINT/.
    # Rehide the background file
    SetFile -a V $MOUNTPOINT/background.png

    hdiutil detach $MOUNTPOINT
    rm -r $MOUNTPOINT

    #set it so the DMG autoopens on download/mount
    hdiutil attach $TEMPLATE -noautoopen -mountpoint /Volumes/"$MOUNT_NAME"
    bless /Volumes/$MOUNT_NAME --openfolder /Volumes/"$MOUNT_NAME"
    hdiutil detach /Volumes/"$MOUNT_NAME"

    if [ -e $FINAL_DMG ] ; then
        rm -r $FINAL_DMG
    fi
    #hdiutil convert $TEMPLATE  -format UDBZ -imagekey -o $FINAL_DMG #bzip2 based is a little bit smaller, but opens much, much slower.
    hdiutil convert $TEMPLATE  -format UDZO -imagekey zlib-level=9 -o $FINAL_DMG #This used zlib, and bzip2 based (above) is slower but more compression

    rm $TEMPLATE
    mkdir -p $DMG_DIR
    mv $FINAL_DMG $DMG_DIR/
}

#TODO: should most of this happen in a tempdir, rather than in the build dir? (I think so...?)

#if [ "${VERBOSE}" ]; then
    set -x
#fi

echo "PACKAGING_DIR: $PACKAGING_DIR"
echo "KICAD_SOURCE_DIR: $KICAD_SOURCE_DIR"
echo "KICAD_INSTALL_DIR: $KICAD_INSTALL_DIR"
echo "VERBOSE: $VERBOSE"
echo "TEMPLATE: $TEMPLATE"
echo "SUPPORT_DIR: $SUPPORT_DIR"
echo "EXTRAS_DIR: $EXTRAS_DIR"
echo "DMG_DIR: $DMG_DIR"
echo "PACKAGE_TYPE: $PACKAGE_TYPE"
echo "pwd: `pwd`"

if [ ! -e "${PACKAGING_DIR}" ]; then
    echo "PACKAGING_DIR must be set and exist."
    exit 1
fi


if [ -z "${TEMPLATE}" ]; then
    echo "TEMPLATE must be set."
    exit 1
fi


if [ -z "${DMG_DIR}" ]; then
    echo "DMG_DIR must be set."
    exit 1
fi

if [ "${PACKAGE_TYPE}" != "nightly" || "${PACKAGE_TYPE}" != "extras" ||  "${PACKAGE_TYPE}" != "unified" ]; then
    echo "PACKAGE_TYPE must be either \"nightly\", \"extras\", or \"unified\"."
    exit 1
fi

if [ "${PACKAGE_TYPE}" != "extras" && ! -e "${SUPPORT_DIR}" ]; then
    echo "In nightly and unified, SUPPORT_DIR must be set and exist."
    exit 1
fi

if [ "${PACKAGE_TYPE}" != "extras" && ! -e "${KICAD_SOURCE_DIR}" ]; then
    echo "In nightly and unified, KICAD_SOURCE_DIR must be set and exist."
    exit 1
fi

if [ "${PACKAGE_TYPE}" != "extras" && ! -e "${KICAD_INSTALL_DIR}" ]; then
    echo "In nightly and unified, KICAD_INSTALL_DIR must be set and exist."
    exit 1
fi

if [ "${PACKAGE_TYPE}" == "extras" &&  -e "${EXTRAS_DIR}" ]; then
    echo "In extras, EXTRAS_DIR must be set and exist."
    exit 1
fi

NOW=`date +%Y%m%d-%H%M%S`

case "${PACKAGE_TYPE}" in 
    nightly)
        KICAD_GIT_REV=`cd $KICAD_SOURCE_DIR && git rev-parse --short HEAD`
        MOUNT_NAME='KiCad'
        DMG_SIZE=1G
    ;;
    extras)
        MOUNT_NAME='KiCad Extras'
        DMG_SIZE=9.5G
    ;;
    unified)
        KICAD_GIT_REV=`cd $KICAD_SOURCE_DIR && git rev-parse --short HEAD`
        MOUNT_NAME='KiCad'
        DMG_SIZE=10G
    ;;
    *)
        echo "PACKAGE_TYPE must be either \"nightly\", \"extras\", or \"unified\"."
        exit 1
esac

MOUNTPOINT=kicad-mnt

setup_dmg

case "${PACKAGE_TYPE}" in 
    nightly)
        mkdir -p $MOUNTPOINT/KiCad
        rsync -al $KICAD_INSTALL_DIR/* $MOUNTPOINT/KiCad/. # IMPORTANT: must preserve symlinks
        #copy in support files
        cp -r $SUPPORT_DIR/* $MOUNTPOINT/kicad
        FINAL_DMG=kicad-nightly-$NOW-$KICAD_GIT_REV.dmg
    ;;
    extras)
        cp -r $EXTRAS_DIR/* $MOUNTPOINT/
        FINAL_DMG=kicad-extras-$NOW.dmg
    ;;
    unified)
        mkdir -p $MOUNTPOINT/KiCad
        rsync -al $KICAD_INSTALL_DIR/* $MOUNTPOINT/KiCad/. # IMPORTANT: must preserve symlinks
        #copy in support files
        cp -r $SUPPORT_DIR/* $MOUNTPOINT/kicad
        FINAL_DMG=kicad-nightly-$NOW-$KICAD_GIT_REV.dmg
    ;;
    *)
        echo "PACKAGE_TYPE must be either \"nightly\", \"extras\", or \"unified\"."
        exit 1
esac

fixup_and_cleanup

echo "Done creating $FINAL_DMG in $DMG_DIR"