# Code issues found while documenting

These issues turned up while the documentation was rewritten and checked
against the code (October 2026). None of them is fixed yet. The
documentation describes the current behavior, except where an entry
says otherwise.

Severity: **medium** gives wrong results without an error; **low** affects
unusual input only.

## 1. Large `page` values read the wrong image (medium)

- **Where:** `lib/Imager/File/SIXEL.pm`, `_readSingle` (line 20) and
  `SIXEL.xs` (`i_readsixel`, `int page`).
- **What:** `_readSingle` only checks `page` against `/\A[0-9]+\z/`.
  The XS typemap then converts the value to a C `int`, which truncates
  values of 2**31 and above.
- **Reproduce:**

  ```perl
  my $data = "\ePq#1~\e\\\ePq#2~~\e\\";
  my $img = Imager->new;
  $img->read(data => $data, type => 'sixel', page => '4294967297');
  # returns the second image (page 1), no error
  ```

  `page => '4294967296'` returns page 0. `page => '2147483648'` fails
  with "page must be a non-negative integer", which is the right
  outcome, but only by accident.
- **Suggested fix:** reject values above 2147483647 in `_readSingle`,
  with the same message.
- **Documentation:** says "a non-negative integer" and does not mention
  the upper bound.

## 2. Reference option values are ignored silently (medium)

- **Where:** `lib/Imager/File/SIXEL.pm`, `_writeSingle` (lines 81-82)
  and `_writeMultiple` (lines 99-100).
- **What:** both ignore the return value of `Imager::_set_opts`. For a
  reference that is neither an array reference nor an Imager::Color,
  `_set_opts` records "Unknown reference type HASH supplied for
  sixel_dither" and stops processing the remaining options. The write
  then succeeds, with that message left in `errstr`. Which of the other
  `sixel_` options were stored before it stopped depends on the hash
  order.
- **Reproduce:**

  ```perl
  $img->write(data => \$sixel, type => 'sixel',
              sixel_dither => {}, sixel_pan => 3, sixel_pad => 2);
  # returns true; the header is "1;1, "3;1, "3;2 or "1;2 depending
  # on the run
  ```

  `write_multi()` behaves the same.
- **Suggested fix:** check the return value of `_set_opts` and fail
  the write.
- **Documentation:** warns against passing such values.

## 3. RGB values in `colors` are not range checked (low)

- **Where:** `lib/Imager/File/SIXEL.pm`, `_paletteColor` (line 46).
- **What:** an array reference is passed straight to
  `Imager::Color->new`, which wraps values outside 0 to 255 instead of
  rejecting them.
- **Reproduce:** `colors => [[300, 0, 0]]` is written as `#0;2;17;0;0`
  (300 mod 256 = 44, which is 17 percent). `[-1, 0, 0]` becomes 255.
  Neither fails.
- **Suggested fix:** reject entries whose values are not integers from
  0 to 255, with "colors entry N is not a valid color".
- **Documentation:** says "red, green and blue values from 0 to 255".

## 4. Keyword options accept an embedded NUL (low)

- **Where:** `sixel_write.c`, `read_keyword_option` (lines 93-108).
- **What:** the tag is copied into a 40 byte buffer and compared with
  `strcmp`. Everything from an embedded NUL byte on is ignored, and
  values of 40 bytes or more are cut short.
- **Reproduce:** `sixel_palette => "webmap\0junk"` is accepted as
  `webmap`. In error messages, values longer than 39 characters are
  shown cut short.
- **Suggested fix:** compare the tag's full length (`size` of the
  `i_img_tag`) as well.

## 5. Rule 4 counts colors before rounding them (low)

- **Where:** `sixel_quant.c`, `sixel_palette_exact` (lines 110-133;
  the rounding to SIXEL percentages happens at line 133).
- **What:** the distinct colors of an image are counted at 8 bits per
  channel, before they are rounded to the 101 SIXEL percentage levels.
  - Colors that round to the same percentages each take a register, so
    the output defines identical registers.
  - An image with more than `sixel_max_colors` 8-bit colors but at most
    `sixel_max_colors` SIXEL colors is quantized and dithered instead
    of being written losslessly. This happens, for example, with
    smooth gradients or with images converted from 16 bits.
- **Reproduce:** pixels (0,0,0) and (1,0,0) give two registers, both
  `0;0;0`.
- **Documentation:** now says that the colors are counted before
  rounding.

## 6. A dying I/O callback leaks C memory (low)

- **Where:** `sixel_write.c` (`write_indexed`, lines 782-805;
  `i_writesixel_multi`, lines 848-857) and the reader.
- **What:** Perl callbacks behind `i_io_write`, `i_io_read` and
  `i_io_close` can `die`. The exception then unwinds through the C
  code.
  - Writer: the output buffer, the band scratch space, the index map
    and the option array are not freed.
  - Reader: the input state and the canvas are not freed.
- **Reproduce:** a `closecb` that dies propagates out of `write()`.
- **Note:** Imager's own codecs behave the same way.

## 7. Spaces inside numeric parameters join digits (low)

- **Where:** `sixel_read.c`, parameter parsing (lines 717-728).
- **What:** spaces and control characters inside a number are skipped
  instead of ending it.
- **Reproduce:** `#1 2;2;100;0;0` defines register 12, not register 1.

## 8. `_writeSingle` stores the `i_` options twice (nitpick)

- **Where:** `lib/Imager/File/SIXEL.pm`, `_writeSingle` (line 81).
- **What:** it calls `_set_opts(\%opts, 'i_', $im)`, which
  `Imager::write` has already done before calling the writer. It is
  harmless.

## Outside this distribution

- **Imager color names depend on `$/`.** `Imager::Color->new('yellow')`
  fails while `$/` is `undef`, for example after a file-scoped
  `local $/;`. Because of this, a color name in `colors` is then
  reported as "colors entry N is not a valid color". This is Imager's
  behavior, not this module's.
- **Integer tags accept a trailing line break.** Imager's `addtag`
  checks integer values with a regular expression ending in `$`, which
  also matches before a final newline, so `sixel_max_colors => "16\n"`
  is stored as the integer 16 and accepted. The documentation says so.
- **Passing `undef` leaves a message in `errstr`.** After a successful
  `write(..., sixel_dither => undef)`, `$img->errstr` holds "No value
  supplied". Imager's `settag` deletes the tag, then `addtag` fails on
  `undef` and records the message, which `_set_opts` ignores. The write
  itself behaves as documented.
- **Imager creates the output file before the writer checks the
  options.** `write(file => 'x.six', sixel_pan => 0)` fails, but
  leaves an empty `x.six`. The documentation says so.
