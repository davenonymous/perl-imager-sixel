# Releasing Imager::File::SIXEL to CPAN

This dist uses plain `ExtUtils::MakeMaker` plus
[`cpan-upload`](https://metacpan.org/pod/cpan-upload) (from
`CPAN::Uploader`). No Dist::Zilla, no Minilla, no surprises.

## Prerequisites

- A C compiler and Imager 1.013 or later with its headers: the dist is
  XS and builds against Imager's extension API (`Imager::ExtUtils`).
- The develop prerequisites from `cpanfile`:

  ```sh
  cpanm --installdeps --with-develop .
  ```

- A `~/.pause` file with your PAUSE credentials, readable only by you:

  ```
  user YOURPAUSEID
  password yourpassword
  ```

## Per-release checklist

1. Make sure the working tree is clean and on `master`, and that the
   last CI run on `master` passed on every Perl and on Windows:

   ```sh
   git status
   git pull --ff-only
   ```

2. Bump `$VERSION` in `lib/Imager/File/SIXEL.pm`. `make release`
   refuses to run if any module under `lib/` disagrees with it
   (`make version-check` runs that guard alone):

   ```sh
   perl -pi -e "s/^(\s*our \\\$VERSION\s*=\s*)'[^']*'/\${1}'1.001'/" $(git ls-files 'lib/*.pm')
   ```

3. Update `Changes`: add a heading for the new version with today's
   date and bullet points describing the changes since the last
   release.

4. Keep `README` in step with the pod in `lib/Imager/File/SIXEL.pm`. It
   is written by hand and ships in the dist, so review it whenever the
   synopsis, the performance figures or the prerequisites changed.

5. If prerequisites changed, update both `Makefile.PL` (what the CPAN
   toolchain reads) and `cpanfile` (what `cpanm --installdeps .` and
   CI read).

6. Sanity-build from a clean slate, including the author tests:

   ```sh
   make distclean 2>/dev/null || true
   perl Makefile.PL
   make
   make test
   prove -b xt
   ```

7. Commit the version bump and `Changes` entry. `make release`
   refuses to run on a dirty tree, so this has to happen first:

   ```sh
   git commit -am "Release v1.001"
   ```

   Use the version from step 2.

8. Cut and upload the release:

   ```sh
   make release
   ```

   The `release` target:

   - Refuses to proceed if any module's `$VERSION` differs from the
     one in `lib/Imager/File/SIXEL.pm`.
   - Refuses to proceed if the git working tree is dirty.
   - Refuses to proceed if a tag `v$(VERSION)` already exists.
   - Runs `make disttest` (builds the dist directory, configures it,
     compiles it and runs its tests; this is what catches missing
     `MANIFEST` entries before they reach CPAN).
   - Runs `make dist` in a second sub-make to build the tarball from
     a fresh dist directory (`disttest` alone does not create one,
     and running both as prerequisites of a single target would pack
     the `blib/` left behind by `disttest`).
   - Refuses to upload if the tarball is missing or contains build
     artefacts (`blib/`, `Makefile`, `MYMETA.*`, `pm_to_blib`, the
     generated `SIXEL.c`, object files). PAUSE does not index such
     tarballs.
   - Runs `cpan-upload` on the freshly built tarball.

9. Tag and push:

   ```sh
   git tag -a "v1.001" -m "Release v1.001"
   git push --follow-tags
   ```

   Use the version from step 2. The tag must be annotated (`-a`):
   `git push --follow-tags` only pushes annotated tags, so a
   lightweight tag would silently stay local.

10. Wait about an hour, then verify on
    [MetaCPAN](https://metacpan.org/dist/Imager-File-SIXEL). PAUSE also
    mails an indexer report; "no modules will be indexed" there means
    the release is broken and needs a bumped re-release. Over the next
    days, check the [CPAN Testers](https://www.cpantesters.org/distro/I/Imager-File-SIXEL.html)
    reports, which cover platforms and compilers CI does not.

## Continuous integration

`.github/workflows/ci.yml` builds and tests the dist on every push and
pull request to `master`:

- on Linux with every Perl from 5.24, the declared minimum, to the
  latest release;
- on Windows with the latest Strawberry Perl, which builds the XS code
  with MinGW gcc and runs `gmake`;
- once more with the latest Perl for the author tests (`prove -b xt`),
  `make version-check` and `make disttest`.

When a new Perl is released, add it at the top of the Linux matrix.

## MANIFEST

`MANIFEST` is checked in. After adding or removing a file, regenerate
it and review the diff before committing:

```sh
perl Makefile.PL
make manifest
git diff MANIFEST
```

`MANIFEST.SKIP` keeps maintainer-only files (this document, `.git*`,
`.github/`, `.claude/`) and build output out of the dist.

`.gitattributes` marks the test fixtures in `t/data/` as binary, so
that Git on Windows does not convert their line endings.

## Recovery

- **Upload failed mid-way.** `cpan-upload` is idempotent against PAUSE
  re-uploads of the *same* tarball; just run `make release` again.
- **Uploaded a broken release.** You have 72 hours to delete it from
  PAUSE via the web UI (`https://pause.perl.org/` -> "Delete
  Files"). After that it is permanent in the BackPAN archive. Either
  way, **never reuse a version number**; bump and re-release.
- **Forgot to bump `$VERSION`.** The `release` target's "tag already
  exists" guard will catch this on the second run, but the tarball
  will already exist locally. Delete it
  (`rm Imager-File-SIXEL-*.tar.gz`), bump the version, and start over.
