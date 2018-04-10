# nix-build-cache

`nix-build-cache` extends `stdenv.mkDerivation` based builds with a distributed
build cache. Many build tools produce intermediate files as part of a build, and
if these intermediate files are present for subsequent build, steps of the build
can be eliminated. `nix-build-cache` manages these files in a somewhat impure
manner, to avoid the output hash changing. Essentially, these build cache files
are purely optimisations and as such shouldn't impact the resulting output.

## Usage

`nix-build-cache` is a function of the following type:

```
{ aws-key : Text
, aws-secret : Text
, pkgs : Nixpkgs
, cache-name : Text
, master-cache : Text
, cache-dirs : List Text
, s3-bucket : Text
} -> stdenv.mkDerivation-result -> stdenv.mkDeriavtion-result
```

where `Nixpkgs` is the object that you'd get from `import <nixpkgs> {}`, and
`stdenv.mkDerivation-result` is the result of a well-formed call to
`stdenv.mkDerivation`. To use `nix-build-cache`, supply the configuration object
and a build that you wish to add a cache to. For example, here's how we can add
a build cache to a build of Aeson:

```nix
let pkgs = import <nixpkgs> {};
    add-build-cache = 
      import 
        ./nix-build-cache.nix 
        {  
          inherit pkgs;
          aws-key = "xxx";
          aws-secret = "xxx";
          cache-name = "aeson";
          master-cache = "aeson";
          cache-dirs = [ "dist" ];
          s3-bucket = "aeson-build";
        };

in add-build-cache pkgs.haskellPackages.aeson
```

The parameters supplied to `nix-build-cache` are:

* `aws-key`: An AWS key
* `aws-secret-key`: An AWS secret key
* `pkgs`: A nixpkgs repository. Used to call things like `mktemp` and `aws`.
* `cache-name`: The name of the cache for this build. A combination of a Git
  repository name and a Git branch name is a good choice here.
* `master-cache`: The name of a fallback cache, if the cache under `cache-name`
  can't be found. If you're building GitHub pull requests, this means the first
  build can resume from the `master` cache.
* `cache-dirs`: Which directories to add to the cache after the build completes.
  For Haskell projects, you will want to use `[ "dist" ]`, and for Elm projects
  `[ "elm-stuff" ]`.
* `s3-bucket`: The name of the S3 bucket to upload the cache to.

## How `nix-build-cache` Works

`nix-build-cache` augments a build by adding some extra steps to `preConfigure`
and `preInstall`.

In `preConfigure`, we first generate an MD5 hash of all files in the source
tree. Next, we attempt to download either `cache-name` or `master-cache` from
S3, and unpack it. This build cache is expected to contain a file - `MD5SUMS` -
which contains the MD5 hash of all source files that produced the cache. We
`join` the current MD5 hashes against these hashes, and work out which have
changed. Any changed files are then `touch`ed to update their timestamp.
Finally, all artifacts in the build cache are `touch`ed to be two hours in the
past. This is an arbitrary time difference, but it's important the build cache
files look they were produced before the changed files were changed. 

In `preInstall`, we simply `tar` up the directories mentioned in `cache-dirs`
and upload this tarball to `cache-name`.

## Limitations

This approach relies on builds having network access.
