{ config, lib, pkgs, ... }:

with lib;
let
  options.services.minimint = {
    enable = mkOption {
    type = types.bool;
    default = true;
    description = ''
      Enable Minimint,is a federated Chaumian e-cash mint backed 
      by bitcoin with deposits and withdrawals that can occur on-chain
      or via Lightning.
    '';
    }; 
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to listen for RPC connections.";
    };
    port = mkOption {
      type = types.port;
      default = 5000;
      description = "Port to listen for RPC connections.";
    };
    extraArgs = mkOption {
      type = types.separatedString " ";
      default = "";
      description = "Extra command line arguments passed to minimint.";
    };
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/minimint";
      description = "The data directory for minimint.";
    };
    user = mkOption {
      type = types.str;
      default = "minimint";
      description = "The user as which to run minimint.";
    };
    group = mkOption {
      type = types.str;
      default = cfg.user;
      description = "The group as which to run minimint.";
    };
    package = mkOption {
      type = types.package;
      default = config.nix-bitcoin.pkgs.minimint;
      defaultText = "config.nix-bitcoin.pkgs.minimint";
      description = "The package providing minimint binaries.";
    };
  };

  cfg = config.services.minimint;
  nbLib = config.nix-bitcoin.lib;
  nbPkgs = config.nix-bitcoin.pkgs;
  runAsUser = config.nix-bitcoin.runAsUserCmd;
  secretsDir = config.nix-bitcoin.secretsDir;
  bitcoind = config.services.bitcoind;

in {
  inherit options;

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    services.bitcoind = {
      enable = true;
      txindex = true;
      regtest = true;
    };
    systemd.services.minimint = {
      wantedBy = [ "multi-user.target" ];
      requires = [ "bitcoind.service" "fedimint-gateway.service" ];
      after = [ "bitcoind.service" "fedimint-gateway.service"  ];
      preStart = ''
        echo "auth = \"${bitcoind.rpc.users.public.name}:$(cat ${secretsDir}/bitcoin-rpcpassword-public)\"" \
          > federation.json
      '';
      serviceConfig = nbLib.defaultHardening // {
      WorkingDirectory = cfg.dataDir;
      ExecStart = ''
        fm_cfg=/var/lib/minimint
        ${config.nix-bitcoin.pkgs.minimint}/bin/configgen $fm_cfg 1 4000 5000 1 10 100 1000 10000 100000 1000000
        ${config.nix-bitcoin.pkgs.minimint}/bin/mint-client-cli $fm_cfg &
        btc_rpc_address="127.0.0.1:8333"
        btc_rpc_user="bitcoin"
        btc_rpc_pass="bitcoin"
        fm_tmp_config="$(mktemp -d)/config.json"

        echo "Writing tmp config to $fm_tmp_config"
        cat $fm_cfg | jq ".wallet.btc_rpc_address=\"$btc_rpc_address\"" \
        | jq ".wallet.btc_rpc_user=\"$btc_rpc_user\"" \
        | jq ".wallet.btc_rpc_pass=\"$btc_rpc_pass\"" > $fm_tmp_config

        $fm_bin $fm_tmp_config &
        ''

       ;
      User = cfg.user;
      Group = cfg.group;
      Restart = "on-failure";
      RestartSec = "10s";
      ReadWritePaths = cfg.dataDir;
      };
    };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      extraGroups = [ "bitcoinrpc-public" ];
    };
    users.groups.${cfg.group} = {};
    nix-bitcoin.operator.groups = [ cfg.group ];
  };
}
