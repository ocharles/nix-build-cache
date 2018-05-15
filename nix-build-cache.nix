{ aws-key
, aws-secret
, pkgs
, cache-name
, master-cache
, cache-dirs
, s3-bucket
}:

let
  s3-uri = file: "s3://${s3-bucket}/${file}";

in

drv:
drv.overrideAttrs (oldAttrs: {
  AWS_ACCESS_KEY_ID = aws-key;
  AWS_SECRET_ACCESS_KEY = aws-secret;

  preConfigure = ''
    echo "-*-*-*-*-"
    echo "nix-build-cache enabled"
    echo "-*-*-*-*-"

    # Before we do anything, capture the MD5 sums of all source files.
    # This is compared against the source files used to produce a cache tarball
    # so we know which files have changed since the cache was made.
    mkdir -p "$out"
    echo "nix-build-cache: Noting current file hashes"
    find . -type f -print0 | xargs -0 md5sum | sort > $out/MD5SUMS

    CACHE_TAR=$( ${pkgs.coreutils}/bin/mktemp )
    echo "nix-build-cache: Downloading latest build cache from S3"
    (
      ${pkgs.awscli}/bin/aws s3 cp "${s3-uri cache-name}" "$CACHE_TAR" \
        || ${pkgs.awscli}/bin/aws s3 cp "${s3-uri master-cache}" "$CACHE_TAR"
      tar xf "$CACHE_TAR"
      rm "$CACHE_TAR"
    ) || echo "nix-build-cache: Cache not found, continuing"

    mkdir -p .cache-meta
    touch .cache-meta/MD5SUMS

    # Touch any files whose MD5SUM has changed since the last build
    join $out/MD5SUMS .cache-meta/MD5SUMS -v 1 | cut -d' ' -f 2 | while read filename; do
      echo "nix-build-cache: $filename" has changed
      touch "$filename" || true
    done

    mv $out/MD5SUMS .cache-meta/MD5SUMS

    # Touch all build cache files to be 2 hours in the past.
    # Note that source code will be last modified in 1970 *by default*
    # but changed to the current time by the loop above.
    find  -print | while read filename; do
        touch -d "$(date -R -r "$filename") - 2 hours" "$filename"
    done

    function uploadCache() {
      CACHE_TAR=$(mktemp)
      (
        echo "Taring build cache"
        tar cfJ "$CACHE_TAR" --mode='a+w' --exclude='*.so' --exclude='*.a' .cache-meta ${toString cache-dirs}

        echo "Uploading latest build cache to S3"
        ${pkgs.awscli}/bin/aws s3 cp "$CACHE_TAR" "${s3-uri cache-name}"

        rm "$CACHE_TAR"
      ) || echo "Failed to tar/upload cache"
    }

    trap 'uploadCache' EXIT

    ${if oldAttrs ? preConfigure then oldAttrs.preConfigure else ""} 
  '';
})
