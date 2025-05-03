script_dir=$(dirname $(realpath $0))
bin_dir=$script_dir/../container_tools
target_dir=${HOME}/.local/bin
for file in $bin_dir/*.sh; do
  filename=$(basename $file)
  if [ -e "$target_dir/$filename" ]; then
    rm -v $target_dir/$filename;
  fi;
  install -Dv -m755 $file $target_dir/$filename
done;
