let
  overlay = self: prev: {
      haskell = prev.haskell // {
        packageOverrides = hnew: hold: with prev.haskell.lib;{

          ip = dontCheck hold.ip;
          bytebuild = dontCheck hold.bytebuild;

          # can be released on more recent nixplks
          # wide-word = doJailbreak (hold.wide-word);

          # for newer nixpkgs (March 2020)
          # base-compat = doJailbreak (hold.base-compat);
          # time-compat = doJailbreak (hold.time-compat);
          mptcp-pm = (overrideSrc hold.mptcp-pm {
            src = prev.fetchFromGitHub {
              owner = "teto";
              repo = "mptcp-pm";
              rev = "4087bd580dcb08919e8e3bc78ec3b25d42ee020d";
              sha256 = "sha256-MiXbj2G7XSRCcM0rnLrbO9L5ZFyh6Z3sPtnH+ddInI8=";
            };
          });
          netlink = (overrideSrc hold.netlink {
            # src = builtins.fetchGit {
            #   # url = https://github.com/ongy/netlink-hs;
            #   url = https://github.com/teto/netlink-hs;
            # };
            src = prev.fetchFromGitHub {
              owner = "teto";
              repo = "netlink-hs";
              rev = "090a48ebdbc35171529c7db1bd420d227c19b76d";
              sha256 = "sha256-qopa1ED4Bqk185b1AXZ32BG2s80SHDSkCODyoZfnft0=";
            };
          });

          # TODO change source
          # bitset = pkgs.haskell.lib.overrideSrc hold.bitset { src = pkgs.fetchFromGithub {
          #     owner = "teto";
          #     repository = "bitset";
          #     rev = "upgrade";
          #     sha256 = "0j0hrzr9b57ifwfhggpzm43zcf6wcsj8ffxv6rz7ni7ar1x96x2c";
          #   };
          # };

        };
      };
  };

  # pinned nixpkgs before cabal 3 becomes the default else hie fails
  nixpkgs = import <nixpkgs>
  # nixpkgs = import (builtins.fetchTarball {
  #     name = "before-libc-update";
  #     url = "https://github.com/nixos/nixpkgs/archive/fa7445532900f2555435076c1e7dce0684daa01a.tar.gz";
  #     sha256 = "1hbf7kmbxmd19hj3kz9lglnyi4g20jjychmlhcz4bx1limfv3c3r";
  # })
  {
    overlays = [ overlay]; config = {allowBroken = true;};
  };
in
  nixpkgs
