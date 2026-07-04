# mAIn OS — Phase 0: headless Firecracker microVM

Buildovatelný skelet spodní vrstvy z [`VISION.md`](./VISION.md) §8c. Minimální,
headless NixOS, který nabootuje jako **Firecracker microVM** a doběhne k běžící
systémové službě **`mAInd`** (agent supervisor stub) — připravené hostit budoucí
agent cell.

## Co je v repu

```
flake.nix            # inputs: nixpkgs + microvm.nix; výstupy: mainos, mainctl, apps
nix/mainos.nix       # headless personalita: microVM nastavení + strip GUI/human cruft
nix/supervisor.nix   # mAInd — supervisor stub jako systemd služba (least-priv sandbox)
scripts/mainctl      # tenké CLI (build / run / info)
```

## Požadavky (na build/run stroji)

- **Nix** s povolenými flakes (`experimental-features = nix-command flakes`).
- Linux x86_64 s **`/dev/kvm`** (Firecracker potřebuje KVM). Bare metal, nebo
  VM s nested virtualizací.
- `firecracker` v PATH (dev shell ho přináší: `nix develop`).

> ⚠️ **Netestováno v tomto containeru.** Session běží bez `nix` i bez `/dev/kvm`,
> takže skelet nebylo možné sestavit ani nabootovat zde. Kód je napsaný idiomaticky
> proti `microvm.nix`; první reálný build proveď na nix+KVM stroji podle níže.

## Build & run

```sh
# 1) build runneru microVM
nix build .#mainos-runner        # nebo: mainctl build

# 2) boot microVM (potřebuje /dev/kvm)
nix run .#mainos                 # nebo: mainctl run
```

Na konzoli (ttyS0) bys měl vidět naskakovat mAInd:

```
[mAInd] mAIn OS supervisor stub — host mainos, kernel 6.x
[mAInd] Phase 0: no agent cells yet; this is where the agent kernel will live.
[mAInd] heartbeat #1 — idle, ready to host agent cells
```

## Dev build (interaktivní shell)

Produkční build je záměrně bez shellu a bez loginu (immutable, headless).
Pro hackování zapni dev toggle v `nix/mainos.nix`:

```nix
mainos.dev = true;   # přidá busybox/htp, serial getty, root heslo "mainos"
```

pak `nix run .#mainos` a přihlaš se na serial konzoli (`root` / `mainos`).

## Síť

Default je jedno `tap` rozhraní (`vm-mainos`) se statickou `10.0.0.2/24`.
Host TAP + routing/NAT je zatím na tobě (pozdější fáze to zautomatizuje přes
`mainctl`). Pro pouhé ověření bootu síť nepotřebuješ.

## Kam to roste

`nix/supervisor.nix` je kotva pro agent kernel (VISION §3.3). Další přírůstky
Phase 1 se věší sem: token/$ rozpočty, snapshot fast-start, MCP tool proxy.
`scripts/mainctl` poroste do control plane (VISION §3.8).
