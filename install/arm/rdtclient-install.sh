#!/usr/bin/env bash

install_dotnet_runtime() {
  msg_info "Installing Dependencies"
  $STD apt-get install -y unzip
  msg_ok "Installed Dependencies"

  msg_info "Installing ASP.NET Core Runtime"
  $STD apt-get install -y libc6 libgcc-s1 libgssapi-krb5-2 liblttng-ust1 libssl3 libstdc++6 zlib1g libicu76
  curl -fsSL -o /tmp/dotnet.tar.gz "https://download.visualstudio.microsoft.com/download/pr/6f79d99b-dc38-4c44-a549-32329419bb9f/a411ec38fb374e3a4676647b236ba021/dotnet-sdk-9.0.100-linux-arm64.tar.gz"
  mkdir -p /usr/share/dotnet
  tar -zxf /tmp/dotnet.tar.gz -C /usr/share/dotnet
  ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
  rm -f /tmp/dotnet.tar.gz
  msg_ok "Installed ASP.NET Core Runtime"
}