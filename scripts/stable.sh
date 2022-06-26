#!/bin/bash
base_dir=/home/runner/work/apt/apt
if [ "$USER" = "krishnakanhaiyakr" ];then
	base_dir=~/apt
fi

set -e
cd $base_dir/scripts
owner=${1:-termux-pod}
repo=${2:-termux-packages}
termux_repo=${3:-termux-main}
#dists=` echo ${3} | cut -d'-' -f2`
dists=${4:-stable}
tag=${5:-debfile}
comp=${6:-main}
pkg_url="https://packages-cf.termux.dev/apt/${termux_repo}/"
# https://github.com/Termux-pod/x11-packages/releases/download/deb/
gh_url="https://github.com/termux-pod/${repo}/releases/download/${tag}/"

export all_in_one=$( mktemp /tmp/all_intmp.XXXXXX )
cached_sums=$base_dir/scripts/cache/$dists
mkdir -p cache
touch $base_dir/scripts/cache/${dists}

fetch() {
		asset_json=$(mktemp /tmp/repo.XXXXXXX)
	     gh api  \
	    -H "Accept: application/vnd.github.v3+json" \
	     https://api.github.com/repos/${owner}/${repo}/releases > $asset_json
}

remote_pkg_list() {
	fetch
	export remote_pkg=$( mktemp /tmp/${repo}.remote.XXXXX )
	jq -r .[].assets[].name $asset_json | sort >  $remote_pkg
}

fetcher() {
	aarch64=$( mktemp /tmp/tmp1.XXXX )
	arm=$( mktemp /tmp/tmp.XXXXXX )
	i636=$( mktemp /tmp/tmp.XXXX )
	x86=$( mktemp /tmp/tmp.XXXXXX )
	#export all_in_one=$( mktemp /tmp/all_intmp.XXXXXX )
		## https://packages.termux.org/apt/termux-x11/dists/x11/main/binary-aarch64/
	curl -f  $pkg_url/dists/${dists}/${comp}/binary-aarch64/Packages -Lo $aarch64
	curl -f  $pkg_url/dists/${dists}/${comp}/binary-arm/Packages -Lo $arm
	curl -f  $pkg_url/dists/${dists}/${comp}/binary-i686/Packages -Lo $i636
	curl -f  $pkg_url/dists/${dists}/${comp}/binary-x86_64/Packages -Lo $x86
	
	cat $aarch64 $arm $i636 $x86 > $all_in_one
	
	
}
# Create list of termux fresh packages
local_pkg_list() {
	fetcher
	local_pkg_list_file=$( mktemp /tmp/pkg_list_local.XXXXXX)
	grep 'Filename:' $all_in_one | cut -d' ' -f2 | \
	sort > $local_pkg_list_file
}

## Create list of pkg which dont contains illegal characters.
compatible_local_pkg_list() {
	export local_pattern=$( mktemp /tmp/pattern.XXXXXX )
	sed 's/[\:\~]/\./g' $local_pkg_list_file | rev | \
	cut -d'/' -f1 | rev  > $local_pattern
	count=1
	compatible_local_list=$(mktemp /tmp/compatie.XXXXXXX)
	for i in `cat $local_pattern`;
	do
		l=`sed -n ${count}p $local_pkg_list_file`
		echo "$i $l" >> $compatible_local_list
		count=$(( count + 1 ))
	done
}


list_missing_pkg_gh() {
	missed_pkg=$(mktemp /tmp/missed.XXXXXX)
	grep -vf $remote_pkg $local_pattern | uniq > $missed_pkg 
}

part1() {
	remote_pkg_list
	local_pkg_list
	compatible_local_pkg_list
	list_missing_pkg_gh
}

part1
## Downloads missing packages and upload it.
d_dir=$(mktemp -d /tmp/d_dir.XXXXXX)
download_missing_pkg() {
	echo ""
	for i in `cat $missed_pkg`;
	do
		pkg=`grep -m1 ^${i} $compatible_local_list | cut -d' ' -f2`
		
		echo "listing.=============>>>==========>>>==================="
		wget -P $d_dir  "${pkg_url}/${pkg}"
		echo "${pkg_url}${pkg}"
		#echo $i
	done
	
}

upload_missing_pkg() {
	echo "Start uploading"
	for i in `ls $d_dir`;
	do
		cd $d_dir
		gh release upload -R github.com/${owner}/${repo} $tag $i
		echo "$i uploaded!"
	done
}

part2() {
	download_missing_pkg
	upload_missing_pkg
}
part2



###### Delete old packages

list_old_pkg() {
	remote_json=$(mktemp /tmp/remote_json.XXXXXX)
	remote_pkg_=$(mktemp /tmp/remote_pkg.XXXXXX)
	old_pkg=$(mktemp /tmp/old_pkg.XXXXXX)
	gh api https://api.github.com/repos/${owner}/${repo}/releases > $remote_json
	
	
	jq -r .[].assets[].name $remote_json > $remote_pkg_
	echo $?
	echo "Wait.." | { grep -vf $local_pattern $remote_pkg_  > $old_pkg || true; }
	
	echo "list_old_pkg Done."
}

# Parse name, assets id so that old packages could be remove easily
delete_old_pkg() {
	echo "Starting delete_old_pkg"
	for i in `cat $old_pkg`;
	do
		echo "Deleting $i"
		url=`jq -r '.[].assets[] | select(.name=='\"$i\"') | .url'  $remote_json`
		echo "" #"
		echo "$url"
		#gh api -X DELETE `jq -r ".[].assets[] | select(.name|test("$i")) | .url" $remote_json`
		gh api -X DELETE $url
		
	done
	echo "Finished!"
}
part3() {
	list_old_pkg
	delete_old_pkg
}

part3


echo "start verifying checksum"
### verify checksums.

verify() {
	local_checksum=$(mktemp /tmp/local_checksum.XXXXXX)
	local_file_name=$(mktemp /tmp/local_filename.XXXXXX)
	local_file_sum=$(mktemp /tmp/local_filename_sum.XXXXXX)
	grep 'Filename: ' $all_in_one | cut -d' ' -f2 > $local_file_name
	grep 'MD5sum: ' $all_in_one | cut -d' ' -f2 > $local_checksum
	
	c=1
	for i in `cat $local_file_name`;
	do
		checksum=`sed -n ${c}p $local_checksum`
		pattern=`echo $i | rev | cut -d'/' -f1 | rev | sed 's/[\:\~]/\./g'`
		echo "$i $checksum $pattern" >> $local_file_sum
		
		c=$(( c + 1 ))
	done
	remote_pkg_list
	tmp_deb_dir=$(mktemp -d /tmp/deb.XXXXX)
	for pkg in `cat $remote_pkg`;
	do
		cd $base_dir/scripts
		if grep --quiet " $pkg" $cached_sums;then
		
			echo "$pkg has already verified"
		else
			echo "$gh_url $pkg"
			cd $tmp_deb_dir
			curl -s -LO -f ${gh_url}${pkg} 
			unset checksum
			unset local_sum
			checksum=$(md5sum ${tmp_deb_dir}/${pkg} | cut -d' ' -f1)
			local_sum=$(grep -m1 " $pkg" $local_file_sum | cut -d' ' -f2)
			echo "local_sum: $local_sum checksum: $checksum"





			
			if [ "$checksum" = "$local_sum" ];then
				echo "$pkg verified"
				cd $base_dir/scripts/
				grep -m1 " $pkg" $local_file_sum  >> $cached_sums
				
			else
				echo "$pkg checksum does't look good"
				echo "Deleting $pkg as require re-upload"
				del_url=`jq -r '.[].assets[] | select(.name=='\"$pkg\"') | .url'  $remote_json` # "
				gh api -X DELETE $del_url
				verified=false
			fi
		fi
	done
		
}

verify 

## Re upload those debs which had wrong checksum

if [ "$verified" = false ]; then
	echo "Re-uploading unmatched checksum debfiles..."
	bash $base_dir/scripts/stable.sh $1 $2 $3 $4 $5 $6
fi
	
