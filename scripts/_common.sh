#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

#=================================================
# PERSONAL HELPERS
#=================================================

romarrng_prepare_data() {
	local directory

	for directory in "$data_dir/library" "$data_dir/rom-hub"; do
		if [[ -L "$directory" ]]; then
			ynh_die --message="Refusing to use a symlink for ROMarrNG data directory: $directory"
		fi
		if [[ -e "$directory" && ! -d "$directory" ]]; then
			ynh_die --message="ROMarrNG data path is not a directory: $directory"
		fi
	done

	if [[ -L "$data_dir/romarr.json" ]]; then
		ynh_die --message="Refusing to read ROMarrNG state through a symlink."
	fi
	if [[ -e "$data_dir/romarr.json" && ! -f "$data_dir/romarr.json" ]]; then
		ynh_die --message="ROMarrNG state path exists but is not a regular file."
	fi

	install -d -o "$app" -g "$app" -m 0750 \
		"$data_dir/library" "$data_dir/rom-hub"
	chmod 0750 "$data_dir"
	chown "$app:$app" "$data_dir"
}

romarrng_install_python_dependencies() {
	local python_dir="/opt/yunohost/romarrng/python-3.12"
	local python_bin="$python_dir/bin/python3.12"
	local python_archive
	local python_sha256
	local python_url
	local python_tmp

	case "$(dpkg --print-architecture)" in
		amd64)
			python_archive="cpython-3.12.14+20260901-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz"
			python_sha256="72748da13197c1fb161e3afeef20a6a385ff24f2165e6e2758e47008e7faba4c"
			;;
		arm64)
			python_archive="cpython-3.12.14+20260901-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz"
			python_sha256="577b4bec0793ad1ff0cbff9adbd0df078eddde38a4c41bf5d83ad381a85ee39d"
			;;
		*) ynh_die --message="ROMarrNG does not provide a Python runtime for this architecture: $(dpkg --print-architecture)" ;;
	esac

	python_tmp="$(mktemp /tmp/romarrng-python.XXXXXX.tar.gz)"
	python_url="https://github.com/astral-sh/python-build-standalone/releases/download/20260901/$python_archive"
	if [[ ! -x "$python_bin" ]]; then
		ynh_script_progression "Installing the pinned Python 3.12 runtime..."
		curl --fail --location --silent --show-error "$python_url" --output "$python_tmp"
		echo "$python_sha256  $python_tmp" | sha256sum --check --status \
			|| ynh_die --message="Downloaded Python runtime failed its SHA-256 check."
		mkdir -p "$python_dir"
		tar --extract --gzip --file="$python_tmp" --directory="$python_dir" --strip-components=1
		rm -f "$python_tmp"
	fi

	ynh_exec_as_app "$python_bin" -m venv "$install_dir/venv"
	ynh_hide_warnings ynh_exec_as_app "$install_dir/venv/bin/pip" install \
		--disable-pip-version-check \
		--no-cache-dir \
		--requirement "$install_dir/requirements.txt" \
		"rom-hub @ https://github.com/BlizzHacker/rom-hub/archive/8e46348783546ee03b00e2c933155ba60d29619d.tar.gz"
}

romarrng_prepare_service() {
	local log_dir="/var/log/$app"
	local log_file="$log_dir/$app.log"

	if [[ -L "$log_dir" ]]; then
		ynh_die --message="Refusing to use a symlink as ROMarrNG's log directory."
	fi
	if [[ -e "$log_dir" && ! -d "$log_dir" ]]; then
		ynh_die --message="ROMarrNG log path exists but is not a directory."
	fi
	install -d -o "$app" -g "$app" -m 0750 "$log_dir"
	install -o "$app" -g "$app" -m 0640 /dev/null "$log_file"

	ynh_config_add_nginx
	ynh_config_add_systemd
	ynh_config_add_logrotate "$log_file"
}

romarrng_start_service() {
	local log_file="/var/log/$app/$app.log"

	ynh_systemctl --service="$app" --action="start" \
		--wait_until="ROMarr listening on" \
		--log_path="$log_file"
}

romarrng_register_service() {
	local log_file="/var/log/$app/$app.log"

	yunohost service add "$app" \
		--description="ROMarrNG game library and acquisition service" \
		--log="$log_file"
}
