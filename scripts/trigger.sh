#!/bin/bash
sudo apt install rclone -y
base_dir=/home/runner/work/apt/apt
if [ "$USER" = "krishnakanhaiyakr" ];then
        base_dir=/tmp/apt
fi

cd $base_dir/scripts
mkdir -p cache
trigger() {
	repo_name=$3
	dist=$4
	comp=$6
	
	old_etag=$(tail -n1 ./cache/${dist}-etag)
	
	src_url=https://packages-cf.termux.dev/apt/${repo_name}/dists/
	curl -I  $src_url/${dist}/Release
	new_etag=$(curl -I  $src_url/${dist}/Release | grep -i ETag | cut -d'"' -f2)
	echo $new_tag
	if [ -z $new_etag ];then
		echo 'new tag is not there'
		return 1
	fi
	
	if [ "$new_etag" != "$old_etag" ];then

		#./${dist}.sh owner repo termux-repo dist tag comp
		./stable.sh $1 $2 $3 $4 $5 $6 
		echo "$new_etag" >> ./cache/${dist}-etag
		rm -r ../${repo_name}
		
		rclone -P -c copyto --http-url $src_url :http: ../${repo_name}/dists/
	
	fi
	
	
		
}

trigger "termux-pod" "termux-packages" "termux-main" "stable" "debfile" "main"
	#sleep 10
trigger "termux-pod" "game-packages" "termux-games" "games" "deb" "stable"
	#sleep 10
trigger "termux-pod" "termux-root-packages" "termux-root" "root" "deb" "stable"
	#sleep 10
trigger "termux-pod" "science-packages" "termux-science" science deb  stable
	#sleep 10
trigger "termux-pod" "unstable-packages" "termux-unstable" unstable deb  main
	#sleep 1
trigger "termux-pod" "x11-packages" "termux-x11" x11 deb  main
	#sleep 10


# Push release files if changes
cd $base_dir
last_commit=$(git log --oneline | head -n1 | cut -d' ' -f1)
list_updated_packages=$(git diff ${last_commit} */*/*/*/*/Packages| cat | grep +Package | sort -u | cut -d' ' -f2)
if [[ `git status --porcelain` ]]; then
  git add .
  git commit -m "Updated $list_updated_packages"
  git push
fi
