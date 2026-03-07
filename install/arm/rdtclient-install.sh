#!/usr/bin/env bash

install_dotnet_runtime() {
  msg_info "Installing Dependencies"
  $STD apt-get install -y unzip
  msg_ok "Installed Dependencies"

  msg_info "Installing ASP.NET Core Runtime"
  $STD apt-get install -y libc6 libgcc-s1 libgssapi-krb5-2 liblttng-ust1 libssl3 libstdc++6 zlib1g libicu76
  curl -fsSL -o /tmp/dotnet.tar.gz "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.103/dotnet-sdk-10.0.103-linux-arm64.tar.gz"
  mkdir -p /usr/share/dotnet
  tar -zxf /tmp/dotnet.tar.gz -C /usr/share/dotnet
  ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
  rm -f /tmp/dotnet.tar.gz
  msg_ok "Installed ASP.NET Core Runtime"
}