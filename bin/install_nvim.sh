script_dir=$(dirname $(realpath $0))
bin_dir=$script_dir/../nvim/bin
target_dir=${HOME}/.local/bin
for file in $bin_dir/*.sh $bin_dir/nvim $bin_dir/nvim_shell $bin_dir/mkchad; do
  filename=$(basename $file)
  if [ -e "$target_dir/$file" ]; then
    rm -v $target_dir/$file;
  fi;
  install -Dv -m755 $file $target_dir
done;
