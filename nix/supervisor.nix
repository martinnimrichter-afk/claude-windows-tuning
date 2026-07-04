# mAIn OS — agent supervisor ("mAInd") stub, Phase 0.
#
# This is the seed of the agent kernel described in VISION.md §3.3. For now it
# just proves the OS boots and reaches a running system service that is *ready*
# to host agent cells. Everything below (scheduling, budgets, tool bus) plugs in
# here later.
{ config, lib, pkgs, ... }:

let
  supervisor = pkgs.writeShellApplication {
    name = "mainos-supervisor";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      echo "[mAInd] mAIn OS supervisor stub — host $(uname -n), kernel $(uname -r)"
      echo "[mAInd] Phase 0: no agent cells yet; this is where the agent kernel will live."
      i=0
      while true; do
        i=$((i + 1))
        echo "[mAInd] heartbeat #$i — idle, ready to host agent cells"
        sleep 10
      done
    '';
  };
in
{
  systemd.services.mainos-supervisor = {
    description = "mAIn OS agent supervisor (mAInd) — Phase 0 stub";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${supervisor}/bin/mainos-supervisor";
      Restart = "always";
      RestartSec = 2;
      DynamicUser = true;
      # Least-privilege sandboxing — foreshadows the capability model in VISION §3.6/§3.7.
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
}
