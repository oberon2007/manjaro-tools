manjaro-tools
=============

Manjaro-tools-0.13

User manual

###1. manjaro-tools.conf

manjaro-tools.conf is the central configuration file for manjaro-tools.
By default, the config is installed in

~~~
/etc/manjaro-tools/manjaro-tools.conf
~~~

A user manjaro-tools.conf can be placed in

~~~
$HOME/.config/manjaro-tools/manjaro-tools.conf
~~~

If the userconfig is present, manjaro-tools will load the userconfig values, however, if variables have been set in the systemwide

~~~
/etc/manjaro-tools/manjaro-tools.conf
~~~

these values take precedence over the userconfig.
Best practise is to leave systemwide file untouched.
By default it is commented and shows just initialization values done in code.

Tools configuration is done in manjaro-tools.conf or by args.
Specifying args will override manjaro-tools.conf settings.

User build lists(eg 'my-super-build.list') can be placed in

~~~
$HOME/.config/manjaro-tools/pkg.list.d
$HOME/.config/manjaro-tools/iso.list.d
~~~

overriding

~~~
/etc/manjaro-tools/pkg.list.d
/etc/manjaro-tools/iso.list.d
~~~


~~~
######################################################
################ manjaro-tools.conf ##################
######################################################

# default target branch
# target_branch=stable

# default taget arch: auto detect
# target_arch=$(uname -m)

# cache dir where buildpkg, buildtree cache packages/pkgbuild, builiso iso files
# cache_dir=/var/cache/manjaro-tools

# build dir where buildpkg or buildiso chroots are created
# chroots_dir=/var/lib/manjaro-tools

# log dir where log files are created
# log_dir='/var/log/manjaro-tools'

# custom build mirror server
# build_mirror=http://mirror.netzspielplatz.de/manjaro/packages

################ buildtree ###############

# manjaro package tree
# repo_tree=('core' 'extra' 'community' 'multilib' 'openrc')

# host_tree=https://github.com/manjaro

# default https seems slow; try this
# host_tree_abs=git://projects.archlinux.org/svntogit

################ buildpkg ################

# default pkg build list; name without .list extension
# build_list_pkg=default

################ buildiso ################

# the name of the profiles directory
# profile_repo='manjaro-tools-iso-profiles'

# default iso build list; name without .list extension
# build_list_iso=default

# the dist name; default: Manjaro
# dist_name="Manjaro"

# the dist release; default: auto
# dist_release=16.10

# the codename; defaults to value sourced from /etc/lsb-release
# dist_codename="Fringilla"

# the branding; default: auto
# dist_branding="MJRO"

# iso publisher
# iso_publisher="Manjaro Linux <http://www.manjaro.org>"

# iso app id
# iso_app_id="Manjaro Linux Live/Rescue CD"

# compression used, possible values xz (default, best compression), gzip, lzma, lzo, lz4
# lz4 is faster but worst compression, may be useful for locally testing isos
# iso_compression=xz

# valid: md5, sha1, sha256, sha384, sha512
# iso_checksum=md5

# possible values: openrc,systemd
# initsys="systemd"

# unset defaults to given value
# kernel="linux44"

# experimental; use overlayfs instead of aufs
# requires minimum 4.0 kernel on the build host and on iso in profile.conf
# use_overlayfs="false"

################ deployiso ################

# the server user
# account=[SetUser]

# set upload bandwidth limit in kB/s
# limit=100
~~~

###2. buildpkg

buildpkg is the chroot build script of manjaro-tools.
It it run in a abs/pkgbuilds directory which contains directories with PKGBUILD.

######manjaro-tools.conf supports the makepkg.conf variables

####Arguments

~~~
$ buildpkg -h
Usage: buildpkg [options]
    -p <pkg>           Buildset or pkg [default: default]
    -a <arch>          Arch [default: auto]
    -b <branch>        Branch [default: stable]
    -r <dir>           Chroots directory
                       [default: /var/lib/manjaro-tools/buildpkg]
    -i <pkg>           Install a package into the working copy of the chroot
    -c                 Recreate chroot
    -w                 Clean up cache and sources
    -n                 Install and run namcap check
    -s                 Sign packages
    -u                 udev base-devel group (no systemd)
    -q                 Query settings and pretend build
    -h                 This help
~~~

######* build sysvinit package for both arches and branch testing:

* i686(buildsystem is x86_64)

~~~
buildpkg -p sysvinit -a i686 -b testing -cwsn
~~~

* for x86_64

~~~
buildpkg -p sysvinit -b testing -cswn
~~~

You can drop the branch arg if you set the branch in manjaro-tools.conf
The arch can also be set in manjaro-tools.conf, but under normal conditions, it is better to specify the non native arch by -a parameter.

######* -c
* Removes the chroot dir
* If the -c parameter is not used, buildpkg will update the existing chroot or create a new one if none is present.

######* -w
* Cleans pkgcache, and logfiles

######* -s
* Signs the package when built

######* -n
* Installs the built package in the chroot and runs a namcap check

######* -u
* Create udev build root (for eudev builds)

###3. buildiso

buildiso is used to build manjaro-iso-profiles. It is run insde the profiles folder.

#####Packages for livecd only:

* manjaro-livecd-cli-installer
* manjaro-livecd-openrc
* manjaro-livecd-systemd

####Arguments

~~~
$ buildiso -h
Usage: buildiso [options]
    -p <profile>       Buildset or profile [default: default]
    -a <arch>          Arch [default: auto]
    -b <branch>        Branch [default: stable]
    -r <dir>           Chroots directory
                       [default: /var/lib/manjaro-tools/buildiso]
    -t <dir>           Target directory
                       [default: /var/cache/manjaro-tools/iso]
    -k <name>          Kernel to use
                       [default: linux44]
    -i <name>          Init system to use
                       [default: systemd]
    -s                 Sign the iso
    -c                 Disable clean work dir
    -x                 Build images only
    -z                 Generate iso only
                       Requires pre built images (-x)
    -w                 Create iso torrent
    -v                 Verbose output to log file, show profile detail (-q)
    -q                 Query settings and pretend build
    -h                 This help
~~~

######* build xfce iso profile for both arches and branch testing on x86_64 build system

* i686 (buildsystem is x86_64)

~~~
buildiso -p xfce -a i686 -b testing
~~~

* for x86_64

~~~
buildiso -p xfce -b testing
~~~

The branch can be defined also in manjaro-tools.conf, but a manual parameter will always override conf settings.

####Special parameters

######* -x
* Build images only
* will stop after all packages have been installed. No iso sqfs compression will be executed

######* -z
* Use this to sqfs compress the chroots if you previously used -x.

###4. check-yaml

check-yaml can be used to write profile package lists to yaml.
It is also possible to generate calamares conf file as buildiso would do.
yaml files are used by calamares netinstall option from a specified url(netgroups).

~~~
$ check-yaml -h
Usage: check-yaml [options]
    -p <profile>       Buildset or profile [default: default]
    -a <arch>          Arch [default: auto]
    -k <name>          Kernel to use[default: linux44]
    -i <name>          Init system to use [default: systemd]
    -c                 Check also calamares yaml files generated for the profile
    -g                 Enable pacman group accepted for -p
    -v                 Validate by schema
    -q                 Query settings
    -h                 This help
~~~
######* build xfce iso profile for both arches and branch testing on x86_64 build system

* i686 (buildsystem is x86_64)

~~~
check-yaml -p xfce -a i686 -c
~~~

* for x86_64

~~~
check-yaml -p xfce -c
~~~

* for a kdebase pacman group with validation

~~~
check-yaml -p kdebase -gv
~~~

####Special parameters

######* -c
* generate calamares module and settings conf files per profile

######* -g
* generate a netgroup for specified pacman group

###5. buildtree

buildtree is a little tools to sync arch abs and manjaro PKGBUILD git repos.

####Arguments

~~~
$ buildtree -h
Usage: buildtree [options]
    -s            Sync manjaro tree
    -a            Sync arch abs
    -c            Clean package tree
    -q            Query settings
    -h            This help
~~~

######* sync arch and manjaro trees

~~~
buildtree -as
~~~

###6. manjaro-chroot

manjaro-chroot is a little tool to quickly chroot into a second system installed on the host.
If the automount option is enabled, manjaro-chroot will detect installed systems with os-prober, and pops up a list with linux systems to select from.
If there is only 1 system installed besides the host system, no list will pop up and it will automatically mount the second system.

####Arguments

~~~
$ manjaro-chroot -h
usage: manjaro-chroot -a [or] manjaro-chroot chroot-dir [command]
    -a             Automount detected linux system
    -q             Query settings and pretend
    -h             Print this help message

    If 'command' is unspecified, manjaro-chroot will launch /bin/sh.

    If 'automount' is true, manjaro-chroot will launch /bin/bash
    and /build/manjaro-tools/manjaro-chroot.
~~~

######* automount

~~~
manjaro-chroot -a
~~~

######* mount manually

~~~
manjaro-chroot /mnt /bin/bash
~~~

###7. deployiso

deployiso is a script to upload a specific iso or a buiildset to SF.
It needs to be run inside the iso-profiles directory.

Ideally, you have a running ssh agent on the host, and your key added, and your public key provided to your SF account. You can then upload without being asked for ssh password.

####Arguments

~~~
$ deployiso -h
Usage: deployiso [options]
    -p                 Source folder to upload [default:default]
    -l                 Limit bandwidth in kB/s [default:80]
    -c                 Create new remote release directory
    -u                 Update remote directory
    -q                 Query settings and pretend upload
    -v                 Verbose output
    -h                 This help
~~~

######* upload official build list, ie all built iso defined in a build list

~~~
deployiso -p official -c
~~~

######* upload xfce

~~~
deployiso -p xfce -c
~~~
