package Imager::File::SIXEL;

use v5.24;
use warnings;
use feature qw(signatures);
no warnings qw(experimental::signatures);
use Imager 1.013;
use Scalar::Util qw(blessed);
use XSLoader;

our $VERSION = '1.000';

XSLoader::load(__PACKAGE__, $VERSION);

use constant MAX_PALETTE_SIZE => 256;

sub _readSingle($im, $io, %opts) {
	my $page = $opts{page} // 0;

	unless ($page =~ /\A[0-9]+\z/) {
		$im->_set_error('page must be a non-negative integer');
		return;
	}
	$im->{IMG} = i_readsixel($io, $page, $opts{allow_incomplete} ? 1 : 0);
	unless ($im->{IMG}) {
		$im->_set_error(Imager->_error_as_msg);
		return;
	}
	return $im;
}

sub _readMultiple($io, %opts) {
	my @images = i_readsixel_multi($io, $opts{allow_incomplete} ? 1 : 0);
	unless (@images) {
		Imager->_set_error(Imager->_error_as_msg);
		return;
	}
	return map { bless { IMG => $_, ERRSTR => undef }, 'Imager' } @images;
}

# Converts one entry of the colors option into an Imager::Color, or
# returns undef.
sub _paletteColor($spec) {
	return unless defined $spec;
	return $spec if blessed($spec) && $spec->isa('Imager::Color');
	return Imager::Color->new($spec->@*) if ref $spec eq 'ARRAY';
	return if ref $spec;
	return Imager::Color->new($spec);
}

# Converts the colors option into an array reference of Imager::Color
# objects. Returns an empty list after recording an error on $target.
sub _paletteOption($target, $colors) {
	return (1, undef) unless defined $colors;

	unless (ref $colors eq 'ARRAY') {
		$target->_set_error('colors must be an array reference');
		return;
	}
	unless ($colors->@* >= 1 && $colors->@* <= MAX_PALETTE_SIZE) {
		$target->_set_error('colors must hold from 1 to ' . MAX_PALETTE_SIZE . ' colors');
		return;
	}

	my @palette;
	foreach my $index (0 .. $colors->$#*) {
		my $color = _paletteColor($colors->[$index]);
		unless ($color) {
			$target->_set_error("colors entry $index is not a valid color");
			return;
		}
		push @palette, $color;
	}
	return (1, \@palette);
}

sub _writeSingle($im, $io, %opts) {
	my ($ok, $palette) = _paletteOption($im, $opts{colors});
	return unless $ok;

	$im->_set_opts(\%opts, 'i_',     $im);
	$im->_set_opts(\%opts, 'sixel_', $im);

	unless (i_writesixel($io, $palette, $im->{IMG})) {
		$im->_set_error(Imager->_error_as_msg);
		return;
	}
	return $im;
}

sub _writeMultiple($class, $io, $opts, @images) {
	unless (@images) {
		$class->_set_error('no images to write');
		return;
	}
	my ($ok, $palette) = _paletteOption($class, $opts->{colors});
	return unless $ok;

	$class->_set_opts($opts, 'i_',     @images);
	$class->_set_opts($opts, 'sixel_', @images);

	unless (i_writesixel_multi($io, $palette, map { $_->{IMG} } @images)) {
		$class->_set_error($class->_error_as_msg);
		return;
	}
	return 1;
}

Imager->register_reader(
	type     => 'sixel',
	single   => \&_readSingle,
	multiple => \&_readMultiple,
);

Imager->register_writer(
	type     => 'sixel',
	single   => \&_writeSingle,
	multiple => \&_writeMultiple,
);

Imager->add_type_extensions('sixel', 'six', 'sixel');
Imager->add_file_magic(name => 'sixel', bits => "\x1BP", mask => 'xx');

1;

__END__

=encoding UTF-8

=head1 NAME

Imager::File::SIXEL - read and write SIXEL images with Imager

=head1 SYNOPSIS

  use Imager;
  use Imager::File::SIXEL;

  # show an image in a SIXEL capable terminal
  my $img = Imager->new(file => 'photo.png')
    or die Imager->errstr;
  my $sixel = '';
  $img->write(data => \$sixel, type => 'sixel')
    or die $img->errstr;
  binmode STDOUT, ':raw';
  print $sixel;

  # write a SIXEL file
  $img->write(file => 'photo.six')
    or die $img->errstr;

  # read a SIXEL file
  my $decoded = Imager->new(file => 'photo.six')
    or die Imager->errstr;

  # every image of a stream holding several
  my @frames = Imager->read_multi(file => 'recording.six', type => 'sixel')
    or die Imager->errstr;

=head1 DESCRIPTION

SIXEL is the bitmap graphics format of DEC's VT200 to VT300 series
terminals. Today it is understood by many terminal emulators, among
them xterm, mlterm, foot, WezTerm, Contour, mintty, Windows Terminal,
iTerm2 and Konsole, which makes it a common way to show images inside
a terminal.

This module adds the C<sixel> file type to L<Imager>. It decodes SIXEL
data into Imager images and encodes Imager images as SIXEL data that
can be written to a terminal. The encoder is written in C and is fast
enough to drive animations: on a current desktop CPU a 640 x 480
frame encodes in 3 to 16 milliseconds, depending on the settings and
the picture (see L</PERFORMANCE>).

Loading the module registers the C<sixel> type for reading and writing,
the file extensions F<.six> and F<.sixel>, and detection of data that
starts with the 7-bit control string introducer C<ESC P>. Imager loads
the module on demand when C<< type => 'sixel' >> is passed explicitly,
but the extensions and the detection are only known after it has been
loaded, so load it with C<use Imager::File::SIXEL> before reading files
without an explicit type.

=head1 THE SIXEL FORMAT

A SIXEL image is a device control string: C<ESC P> (or the 8-bit
control character 0x90), up to three numeric parameters, the letter
C<q>, the image data, and the string terminator C<ESC \> (or 0x9C).
The image data paints the picture in horizontal bands six pixels high.
Each data character from C<?> to C<~> encodes one column of a band: the
character code minus 63 is a six bit mask whose lowest bit is the top
pixel. Other commands select or define colour registers (C<#>), repeat
the next character (C<!>), return to the start of the band (C<$>), move
to the next band (C<->) and declare the pixel aspect ratio and the
image size (C<">).

Colours are defined as percentages from 0 to 100 per RGB channel, or
in the HLS colour space. SIXEL can therefore represent 101 levels per
channel, not 256: when an image is written, every colour is rounded to
the nearest of these levels. Reading the result back yields the same
rounded values; writing them again is lossless.

=head1 READING

  my $img = Imager->new;
  $img->read(file => 'image.six', type => 'sixel')
    or die $img->errstr;

  my @images = Imager->read_multi(file => 'stream.six', type => 'sixel')
    or die Imager->errstr;

The input is scanned for SIXEL control strings, that is control strings
whose final character is C<q> and that have neither intermediate
characters nor a private marker. Text, escape sequences and other
control strings before, between and after them are skipped, so a
recording of terminal output can be read directly. Each SIXEL control
string is one image. Both the 7-bit and the 8-bit forms of the
introducer and the terminator are recognized; a byte 0x90 that
continues a UTF-8 encoded character of the surrounding text is not
taken as an introducer.

A SIXEL image ends with its string terminator, with any other escape
sequence (which is then examined as the possible start of the next
image), or with the control characters CAN (0x18) or SUB (0x1A).
Spaces, line breaks and other control characters inside the data are
ignored, as are characters without a meaning in SIXEL.

C<read_multi()> returns every image of the input, or fails as a whole
if any image cannot be read.

=head2 Read options

=over

=item page

The zero based index of the image to read with C<read()>, a
non-negative integer, 0 by default.

=item allow_incomplete

If true, an image cut short by the end of the input is returned with
the C<i_incomplete> tag set to 1. Otherwise such an image makes the
read fail. This also applies to the last image read by
C<read_multi()>.

=back

=head2 The decoded image

=over

=item *

The image is as wide and as high as the painted area: one pixel past
the rightmost and the lowest pixel whose bit is set. If raster
attributes (C<">) before the first data character declare a larger
size, the image has at least that size. Bits that are not set do not
enlarge the image, so the height is not rounded up to a multiple of
six. Raster attributes after the first data character are ignored, as
on DEC terminals.

=item *

If the second parameter of the control string (P2) is 1, pixels that
were never painted are transparent and the image has four channels
(RGBA). Otherwise the image has three channels (RGB) and unpainted
pixels take the final colour of register 0, which acts as the
background colour as on DEC terminals.

=item *

Each pixel keeps the colour its register held when the pixel was
painted. Some encoders, such as C<img2sixel -I> from libsixel,
redefine registers during an image to show more colours than there
are registers; their images decode as intended. DEC terminals, xterm
and libsixel instead recolour the pixels painted earlier when a
register is redefined. Both interpretations give the same result for
images that define each register once, as nearly all encoders,
including this one, do. An image can have up to 65534 colours this
way; beyond that, redefining a register recolours its earlier pixels.

=item *

The colours of an image are counted as one per register used, one
more for each redefinition of a register that had painted pixels, and
one for the background if any pixel is unpainted. If there are at
most 256, the image is a paletted image
(C<< $img->type eq 'paletted' >>). Its palette holds the colours used,
in register order, then colours from redefined registers in the order
they were defined, then a transparent entry if unpainted pixels are
transparent; two entries may hold the same colour. Otherwise it is a
direct colour image with 8 bits per sample.

=item *

There are 1024 colour registers; higher register numbers wrap around
(register 1025 is register 1). Registers 0 to 15 start with the colour
map of the VT340, all others start black. Register 15 is selected
until the data selects another one. A colour definition also selects
its register.

=item *

RGB colour definitions above 100% are treated as 100%. HLS
definitions use the DEC hue circle, on which blue is at 0 degrees, red
at 120 and green at 240; hues above 360 are treated as 360, and
lightness and saturation above 100 as 100. Colour
definitions in other colour spaces are ignored, but still select the
register.

=item *

The pixel aspect ratio is not applied: every SIXEL pixel becomes one
image pixel. The ratio is reported in tags (see below). To display an
image with non-square pixels correctly, scale it:

  my ($pan, $pad) = map { $img->tags(name => $_) } qw(sixel_pan sixel_pad);
  $img = $img->scale(
    xpixels => $img->getwidth,
    ypixels => int($img->getheight * $pan / $pad + 0.5),
    type    => 'nonprop',
  ) if $pan != $pad;

=item *

Images larger than the limits set with C<< Imager->set_file_limits >>
are rejected, whether the size is declared or painted; by default
Imager limits only the memory of an image, to 1 GiB. The repeat
command lets a few bytes paint many pixels, and the same pixels can
be painted over any number of times. The limits bound the memory
used; decoding stops with an error once an image has painted 16 times
as many pixels as its storage holds, which bounds the time as well.
With large limits that is still a lot of work for little input, so
before reading untrusted data, set limits that fit your application
and limit the size of the input you accept:

  Imager->set_file_limits(width => 4096, height => 4096,
                          bytes => 64 * 1024 * 1024);

=back

=head2 Tags set when reading

=over

=item i_format

C<sixel>.

=item sixel_pan, sixel_pad

The pixel aspect ratio as height (C<sixel_pan>) to width
(C<sixel_pad>). It comes from the raster attributes if present, and
otherwise from the first control string parameter (P1): 5:1 for P1 2;
3:1 for 3 or 4; 1:1 for 7, 8 or 9; and 2:1 for any other value or
without P1. Since practically all current encoders, including this
one, declare 1:1 in the raster attributes, these tags are usually both
1.

Both tags are written back by the encoder, so an image read and
written again keeps its aspect ratio.

=item i_incomplete

1 for an image cut short by the end of the input, see
L</allow_incomplete>.

=back

=head1 WRITING

  $img->write(file => 'image.six')
    or die $img->errstr;

  my $sixel = '';
  $img->write(data => \$sixel, type => 'sixel', sixel_dither => 'ordered')
    or die $img->errstr;

  Imager->write_multi({ file => 'frames.six', type => 'sixel' }, @frames)
    or die Imager->errstr;

Each image is written as one SIXEL control string of the form

  ESC P 0 ; P2 ; 0 q " Pan ; Pad ; width ; height  colour definitions  bands  ESC \

where P2 is 1 for images with an alpha channel and 0 otherwise, and
C<Pan;Pad> is the pixel aspect ratio, normally 1;1. Only the 7-bit
forms of the control characters are written, so the data is plain
ASCII. Colours are defined in RGB percentages, only colour registers
that are used are defined, each register is defined once, and the
registers used are 0 to 255.

C<write_multi()> writes the images one after another, each as an
independent control string; nothing is written between them. The
options of all images are checked before anything is written.

=head2 Write options

Options whose names start with C<sixel_> are stored as tags on the
image before it is written, following the usual Imager convention, so
they can equally be set as tags, and they stay on the image for later
writes. Pass every option you rely on, or delete the tag with
C<< $img->deltag(name => ...) >>, when writing the same image again
with different settings.

Numeric options must be decimal integers. Invalid values make the
write fail with a message naming the option, before anything is
written. An invalid value is stored as a tag like a valid one, so
later writes of the same image fail in the same way until the option
is passed with a valid value or the tag is deleted.

=over

=item sixel_palette

The kind of palette used when the image is not written with its own
colours; L</How the palette is chosen> gives the precedence:

=over

=item C<adaptive>

The default. A palette of at most C<sixel_max_colors> colours computed
from the image: its colour histogram is divided into boxes, always
splitting the box whose split removes the most squared error, and the
box means are then refined by two rounds of k-means. The palette
therefore differs from image to image.

=item C<webmap>

The 216 colour web-safe palette, a 6 x 6 x 6 cube with the levels 0,
20, 40, 60, 80 and 100 percent. The palette is the same for every
image, and computing it costs nothing.

=back

=item sixel_max_colors

From 1 to 256, 256 by default: the largest number of colours of an
adaptive palette, and the largest number of colours with which an
image is written with its own colours (rules 3 and 4 of
L</How the palette is chosen>). Fewer colours make the output smaller
and the terminal faster, at the cost of quality. It does not limit the
C<webmap> palette or a palette passed with L</colors>.

=item sixel_dither

How pixels are mapped to palette colours that do not match them
exactly:

=over

=item C<diffusion>

The default. Floyd-Steinberg error diffusion in serpentine order. It
gives the best still images, but a change anywhere in the picture
alters the dot pattern of everything below it, which flickers in
animations.

=item C<ordered>

An 8 x 8 Bayer matrix whose strength follows the spacing of the
palette colours. The pattern is fixed to the pixel position, so with a
fixed palette (C<webmap> or L</colors>) the areas of a picture that
did not change stay unchanged from frame to frame.

=item C<none>

Each pixel takes the palette colour nearest to it in RGB space, ties
going to the lower register. This gives the smallest output, but
smooth gradients show bands.

=back

When dithering, colours are matched on a grid of 64 levels per
channel; the dithering absorbs the difference. Images written with
their own colours, rules 3 and 4 of L</How the palette is chosen>, are
never dithered.

=item colors

An array reference of 1 to 256 colours to use as the palette. Each
entry is an L<Imager::Color> object, an array reference of red, green
and blue values from 0 to 255, or a string C<< Imager::Color->new >>
accepts, such as C<'#FF8000'> or C<'red'>:

  $img->write(data => \$sixel, type => 'sixel',
              colors => ['#000000', [255, 255, 255], 'red']);

It takes precedence over C<sixel_palette> and C<sixel_max_colors>. The
colours are rounded to SIXEL percentages and pixels are mapped and
dithered as set by C<sixel_dither>. Unlike the C<sixel_> options it is
not stored on the image.

=item sixel_alpha_threshold

For images with an alpha channel: pixels whose alpha is below this
value, from 0 to 255, are left unpainted, so the terminal background
shows through; all other pixels are painted with their colour,
ignoring their alpha. The default is 128. A value of 0 paints every
pixel.

=item sixel_pan and sixel_pad

The pixel aspect ratio written to the raster attributes, as positive
integers, 1 and 1 by default. Terminals that honour the ratio draw
each pixel C<sixel_pan / sixel_pad> times as high as it is wide.

=back

=head2 How the palette is chosen

The first rule that applies decides:

=over

=item 1.

If L</colors> is given, that palette is used.

=item 2.

If C<sixel_palette> is C<webmap>, the web-safe palette is used.

=item 3.

If the image is paletted and its palette has at most
C<sixel_max_colors> entries, the image palette is used and colour
register I<n> holds palette entry I<n>. This is the fastest path and
is lossless apart from the rounding to SIXEL percentages; use it to
control the palette yourself, for example with
C<< $img->to_paletted(...) >>.

=item 4.

If the image has at most C<sixel_max_colors> distinct colours, these
colours are used.

=item 5.

Otherwise an adaptive palette is computed.

=back

=head2 Image types

Images of any type and sample size can be written. Grey images are
written as RGB. Samples with more than 8 bits are reduced to 8 bits
before the colours are rounded to SIXEL percentages. Images with an
alpha channel, grey or colour, are written with P2 = 1, so that
unpainted pixels are transparent; see L</sixel_alpha_threshold>.

=head1 DISPLAYING IMAGES IN A TERMINAL

The SIXEL data is drawn at the text cursor; the cursor then moves to
the line below the image in most terminals. Write the data unmodified,
with the output handle set to C<:raw> so that no I/O layer, such as
the line ending translation of C<:crlf>, alters it.

  use Imager;
  use Imager::File::SIXEL;

  my $img = Imager->new(file => shift)
    or die Imager->errstr;

  # fit into 800 x 600 pixels, keeping the aspect ratio
  $img = $img->scale(xpixels => 800, ypixels => 600, type => 'min')
    if $img->getwidth > 800 || $img->getheight > 600;

  my $sixel = '';
  $img->write(data => \$sixel, type => 'sixel')
    or die $img->errstr;

  binmode STDOUT, ':raw';
  print $sixel, "\n";

To write straight to a file handle, pass it as C<fh>:

  $img->write(fh => \*STDOUT, type => 'sixel')
    or die $img->errstr;

A terminal that supports SIXEL lists C<4> among the parameters of its
response to the primary device attributes request C<ESC [ c>. Some
need it enabled. xterm, for example, needs to emulate a VT340 and, for
images with more than 16 colours, more colour registers than the
VT340's 16:

  xterm -ti vt340 -xrm 'XTerm*numColorRegisters: 256'

Terminals with fewer than 256 colour registers show images with more
colours wrongly. For them, set C<sixel_max_colors> to their register
count and do not use the C<webmap> palette, which needs 216
registers; a palette passed with L</colors> must not have more entries
than the terminal has registers. Terminal multiplexers such as tmux and GNU screen pass
SIXEL data through only if they support it and are configured to.

Large images take long to transfer and draw; scaling them to the size
they should appear at is the most effective way to speed up display.

=head1 ANIMATION

The encoder is designed to keep up with real time animation. Encode
each frame into a buffer and draw it at a fixed position:

  use Imager;
  use Imager::File::SIXEL;
  use Time::HiRes qw(sleep time);

  binmode STDOUT, ':raw';
  STDOUT->autoflush(1);

  print "\e[?25l\e[2J";    # hide the cursor, clear the screen
  my $fps = 60;
  my $start = time;
  for my $n (0 .. 599) {
    my $frame = render_frame($n);    # returns an Imager object

    my $sixel = '';
    $frame->write(data => \$sixel, type => 'sixel',
                  sixel_palette => 'webmap', sixel_dither => 'ordered')
      or die $frame->errstr;

    # move to the top left corner and draw the frame as one
    # synchronized update
    print "\e[?2026h\e[H", $sixel, "\e[?2026l";

    my $wait = $start + ($n + 1) / $fps - time;
    sleep $wait if $wait > 0;
  }
  print "\e[?25h\n";    # show the cursor again

C<ESC [ ? 2026 h> and C<ESC [ ? 2026 l> start and end a synchronized
update, which keeps the terminal from showing half drawn frames;
terminals that do not support it ignore them. The frame must fit into
the terminal window with at least one text line to spare below it;
otherwise the terminal scrolls after each frame and the frames jump.
The script F<examples/sixel-animate.pl> in the distribution is a
complete version of this loop.

Recommendations for animations:

=over

=item *

Use a fixed palette: C<< sixel_palette => 'webmap' >>, or one palette
computed for the whole animation and passed with L</colors>:

  my @palette = Imager->make_palette({ make_colors => 'mediancut' },
                                     @sample_frames);
  $frame->write(data => \$sixel, type => 'sixel',
                colors => \@palette, sixel_dither => 'ordered');

An adaptive palette is computed for each frame, and any change to the
picture can change the palette and with it every pixel of the frame.

=item *

Use C<< sixel_dither => 'ordered' >> or C<< sixel_dither => 'none' >>.
With a fixed palette, both leave unchanged areas unchanged; error
diffusion does not.

=item *

The terminal, not the encoder, usually limits the frame rate: it has
to receive, parse and draw every frame. Smaller frames, fewer colours
(C<sixel_max_colors>), C<webmap> and C<< sixel_dither => 'none' >> all
reduce the amount of data per frame.

=back

=head1 PERFORMANCE

The encoder builds the palette from a colour histogram, maps the
pixels through a lookup table of nearest palette colours, and emits
the SIXEL data band by band. Each band's pixels are bucketed by colour
in linear time, split into runs of columns, and packed onto as few
sixel lines as possible; in fully painted bands the first line paints
whole columns, which later lines paint over, so that it compresses
into long repeats. On the test images, the output for the same pixels
was typically 4 to 20 percent smaller than that of libsixel 1.10.5
with adaptive palettes, and more with fixed palettes; for very simple
images both are about the same size.

These are the times for one complete C<< $img->write(data => \$buffer,
type => 'sixel') >> call, measured with F<examples/sixel-bench.pl>,
whose output is condensed here, on an Intel Core i5-12600K with Perl
5.38 and Imager 1.033. The "synthetic" picture is the benchmark's
default, smooth gradients with noise; the "photo" is F<snake.png> from
the libsixel distribution, a photograph with fine detail, which is
about the hardest case for the encoder.

                               synthetic                photo
  size      dither     palette   ms  frames/s   bytes      ms  frames/s   bytes
  256x256   diffusion  adaptive  2.1      472   70607     5.5      182   98613
  256x256   ordered    adaptive  1.5      685   65440     3.7      270  110899
  256x256   none       adaptive  1.7      603   65944     4.8      207   89583
  256x256   ordered    webmap    0.9     1155   36965     1.5      680   52080
  256x256   none       webmap    0.6     1629    9256     1.5      673   25949
  192x128   diffusion  adaptive  0.9     1073   27619     3.1      324   45451
  192x128   ordered    adaptive  0.7     1483   26704     2.4      419   49446
  192x128   none       adaptive  0.8     1307   26971     2.9      342   42365
  192x128   ordered    webmap    0.5     2200   15222     0.8     1277   22875
  192x128   none       webmap    0.3     3814    3885     0.8     1280   12476
  640x480   diffusion  adaptive  8.9      112  373095    15.4       65  341301
  640x480   ordered    adaptive  5.8      172  329641     8.7      115  389983
  640x480   none       adaptive  6.4      157  329569    11.4       88  267180
  640x480   ordered    webmap    3.3      305  160163     4.3      231  203313
  640x480   none       webmap    3.0      335   49565     4.2      236   73404

Every setting encodes all three sizes of both pictures at more than 60
frames per second on this machine; at 640 x 480 the default settings
leave the least headroom, which is why ordered dithering is
recommended for animations. Run F<examples/sixel-bench.pl>, which
accepts C<--file>, to measure your machine and pictures. Decoding a
640 x 480 image takes about 5 milliseconds.

=head1 DIAGNOSTICS

Failures are reported through C<< $img->errstr >> or
C<< Imager->errstr >> as usual. The messages specific to this module
are:

=over

=item no SIXEL image found

The input holds no SIXEL control string.

=item SIXEL page N not found

The input holds fewer images than the C<page> option asks for.

=item page must be a non-negative integer

The C<page> option is not a non-negative integer.

=item premature end of SIXEL data

The input ends inside an image; see L</allow_incomplete>.

=item SIXEL image contains no pixels

An image paints no pixel and declares no size, so there is nothing to
return.

=item SIXEL data paints too many pixels

The data paints over the same pixels far more often than any real
image does; see L</The decoded image>.

=item image dimensions are too large

=item file size limit - ...

The image is larger than the limits set with
C<< Imager->set_file_limits >> or than the decoder supports.

=item sixel_max_colors must be an integer from 1 to 256

=item sixel_alpha_threshold must be an integer from 0 to 255

=item sixel_pan must be an integer from 1 to 2147483647

=item sixel_pad must be an integer from 1 to 2147483647

=item unknown sixel_palette value '...'

=item unknown sixel_dither value '...'

=item colors must be an array reference

=item colors must hold from 1 to 256 colors

=item colors entry N is not a valid color

An invalid write option; see L</Write options>.

=item no images to write

C<write_multi()> was called without images.

=item image too large to encode

The image is too wide or too large to fit the encoder's buffers in
memory.

=item read failed, write failed, error closing output

The underlying file or handle reported an error.

=item out of memory

Memory could not be allocated.

=back

=head1 LIMITATIONS

=over

=item *

The encoder uses at most 256 colour registers per image. The decoder
accepts up to 1024.

=item *

Colours are limited to the 101 levels per channel that SIXEL's
percentages can express.

=item *

Semi-transparent pixels are either painted fully or not at all, see
L</sixel_alpha_threshold>. SIXEL has no partial transparency.

=item *

The decoder does not stretch images with a pixel aspect ratio other
than 1:1; see L</The decoded image>.

=item *

The horizontal grid size parameter (P3) of the control string is
ignored, as by current terminals.

=back

=head1 SEE ALSO

L<Imager>, L<Imager::Files>, L<Imager::ImageTypes>.

The SIXEL chapter of the VT330/VT340 Programmer Reference Manual:
L<https://vt100.net/docs/vt3xx-gp/chapter14.html>.

libsixel, the reference implementation of SIXEL encoding and decoding:
L<https://github.com/libsixel/libsixel>.

=head1 AUTHOR

davenonymous E<lt>dave@davenonymous.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2026 davenonymous.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
