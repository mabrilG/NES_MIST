// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

module video(
	input  clk,
	input [5:0] color,
	input [8:0] count_h,
	input [8:0] count_v,
	input mode,
	input ypbpr,
	input smoothing,
	input scanlines,
	input overscan,
	input palette,
	
	input sck,
	input ss,
	input sdi,

	output       VGA_HS,
	output       VGA_VS,
	output [5:0] VGA_R,
	output [5:0] VGA_G,
	output [5:0] VGA_B,
	
	output osd_visible
);

reg clk2 = 1'b0;
always @(posedge clk) clk2 <= ~clk2;
wire clkv = mode ? clk2 : clk;

wire [5:0] R_out, G_out, B_out;

osd #(10'd0, 10'd0, 3'd4) osd (
   .pclk(clkv),

   .sck(sck),
   .sdi(sdi),
   .ss(ss),

   .red_in  ({vga_r, vga_r[4]}),
   .green_in({vga_g, vga_g[4]}),
   .blue_in ({vga_b, vga_b[4]}),
   .hs_in(sync_h),
   .vs_in(sync_v),

   .red_out(R_out),
   .green_out(G_out),
   .blue_out(B_out),

	.osd_enable(osd_visible)
);

// NTSC UnsaturatedV6 palette
//see: http://www.firebrandx.com/nespalette.html
wire [15:0] pal_unsat_lut[64] = '{
	'h35ad, 'h4060, 'h4823, 'h4027, 'h302b, 'h140b, 'h004a, 'h0068,
	'h00c6, 'h0121, 'h0120, 'h0d00, 'h2ce0, 'h0000, 'h0000, 'h0000,
	'h5ad6, 'h6943, 'h74c9, 'h748e, 'h5873, 'h3074, 'h0cb4, 'h0130,
	'h01ac, 'h0205, 'h0220, 'h2200, 'h49e0, 'h0000, 'h0000, 'h0000,
	'h7fff, 'h7eac, 'h7e32, 'h7dd7, 'h7ddc, 'h65be, 'h361e, 'h167b,
	'h02f7, 'h0350, 'h1f6b, 'h3f49, 'h6729, 'h294a, 'h0000, 'h0000,
	'h7fff, 'h7f98, 'h7f5a, 'h7f3c, 'h7f3f, 'h7b3f, 'h635f, 'h577e,
	'h4fbd, 'h4fda, 'h5bd7, 'h67d6, 'h77d6, 'h5ef7, 'h0000, 'h0000
};

// FCEUX palette
wire [15:0] pal_fcelut[64] = '{
	'h39ce, 'h4464, 'h5400, 'h4c08, 'h3811, 'h0815, 'h0014, 'h002f,
	'h00a8, 'h0100, 'h0140, 'h08e0, 'h2ce3, 'h0000, 'h0000, 'h0000,
	'h5ef7, 'h75c0, 'h74e4, 'h7810, 'h5c17, 'h2c1c, 'h00bb, 'h0539,
	'h01d1, 'h0240, 'h02a0, 'h1e40, 'h4600, 'h0000, 'h0000, 'h0000,
	'h7fff, 'h7ee7, 'h7e4b, 'h7e28, 'h7dfe, 'h59df, 'h31df, 'h1e7f,
	'h1efe, 'h0b50, 'h2769, 'h4feb, 'h6fa0, 'h3def, 'h0000, 'h0000,
	'h7fff, 'h7f95, 'h7f58, 'h7f3a, 'h7f1f, 'h6f1f, 'h5aff, 'h577f,
	'h539f, 'h53fc, 'h5fd5, 'h67f6, 'h7bf3, 'h6318, 'h0000, 'h0000
};

wire [14:0] pixel = palette ?  pal_unsat_lut[color][14:0] : pal_fcelut[color][14:0];
 
// Horizontal and vertical counters
reg [9:0] h, v;
wire hpicture  = (h < 512);             // 512 lines of picture
wire hend = (h == 681);                 // End of line, 682 pixels.
wire vpicture = (v < (480 >> mode));    // 480 lines of picture
wire vend = (v == (523 >> mode));       // End of picture, 524 lines. (Should really be 525 according to NTSC spec)

wire [14:0] doubler_pixel;
wire doubler_sync;

Hq2x hq2x(clk, pixel, smoothing,        // enabled 
            count_v[8],                 // reset_frame
            (count_h[8:3] == 42),       // reset_line
            {v[0], h[9] ? 9'd0 : h[8:0] + 9'd1}, // 0-511 for line 1, or 512-1023 for line 2.
            doubler_sync,               // new frame has just started
            doubler_pixel);             // pixel is outputted

reg [8:0] old_count_v;
wire sync_frame = (old_count_v == 9'd511) && (count_v == 9'd0);
always @(posedge clkv) begin
  h <= (hend || (mode ? sync_frame : doubler_sync)) ? 10'd0 : h + 10'd1;
  if(mode ? sync_frame : doubler_sync) v <= 0;
    else if (hend) v <= vend ? 10'd0 : v + 10'd1;

  old_count_v <= count_v;
end

wire [14:0] pixel_v = (!hpicture || !vpicture) ? 15'd0 : mode ? pixel : doubler_pixel;
wire darker = !mode && v[0] && scanlines;

// display overlay to hide overscan area
// based on Mario3, DoubleDragon2, Shadow of the Ninja
wire ol = overscan && ( (h > 512-16) || 
								(h < 20) || 
								(v < (mode ? 6 : 12)) || 
								(v > (mode ? 240-10 : 480-20)) 
							  );

wire  [4:0]   vga_r = ol ? {4'b0, pixel_v[4:4]}   : (darker ? {1'b0, pixel_v[4:1]} : pixel_v[4:0]);
wire  [4:0]   vga_g = ol ? {4'b0, pixel_v[9:9]}   : (darker ? {1'b0, pixel_v[9:6]} : pixel_v[9:5]);
wire  [4:0]   vga_b = ol ? {4'b0, pixel_v[14:14]} : (darker ? {1'b0, pixel_v[14:11]} : pixel_v[14:10]);
wire         sync_h = ((h >= (512 + 23 + (mode ? 18 : 35))) && (h < (512 + 23 + (mode ? 18 : 35) + 82)));
wire         sync_v = ((v >= (mode ? 240 + 5  : 480 + 10))  && (v < (mode ? 240 + 14 : 480 + 12)));

video_mixer video_mixer
(
	.scandoubler_disable(mode),
	.ypbpr(ypbpr),
	.ypbpr_full(1),

	.r_i({R_out, R_out[5:4]}),
	.g_i({G_out, G_out[5:4]}),
	.b_i({B_out, B_out[5:4]}),
	.hsync_i(sync_h),
	.vsync_i(sync_v),

	.r_p({R_out, R_out[5:4]}),
	.g_p({G_out, G_out[5:4]}),
	.b_p({B_out, B_out[5:4]}),
	.hsync_p(sync_h),
	.vsync_p(sync_v),

	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B)
);

endmodule
