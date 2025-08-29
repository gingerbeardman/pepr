#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include <ImageIO/ImageIO.h>
#include <CoreGraphics/CoreGraphics.h>
#define PEP_IMPLEMENTATION
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunsequenced"
#endif
#include "PEP.h"
#if defined(__clang__)
#pragma clang diagnostic pop
#endif

static void print_usage(const char* prog){
	fprintf(stderr,
		"Usage:\n"
		"  %s --demo <out.pep>                Generate a 32x32 demo image.\n"
		"  %s --rgba <w> <h> <in.rgba> <out.pep>  Convert raw RGBA32 to .pep\n"
		"  %s --image <in.img> <out.pep>       Convert image (PNG/TIFF/etc) to .pep\n"
		"  %s --dry-run <in.img>               Encode image to memory only (benchmark)\n"
		"  %s --to-bmp <in.pep> <out.bmp>      Convert .pep to 32-bit BMP\n"
		"  %s --to-rle-bmp <in.pep> <out.rle>  Convert .pep to 8-bit RLE BMP (.rle)\n"
		"  %s <in> [out]                        Auto: .pep→.bmp, else img→.pep\n"
		"\nNotes:\n  - <in.rgba> must be width*height*4 bytes (RGBA8).\n",
		prog, prog, prog, prog, prog, prog, prog);
}

static int has_ext_ci( const char* const path, const char* const ext )
{
	if( !path || !ext ) return 0;
	size_t lp = strlen( path );
	size_t le = strlen( ext );
	if( lp < le ) return 0;
	const char* s = path + ( lp - le );
	for( size_t i = 0; i < le; i++ )
	{
		char a = s[ i ];
		char b = ext[ i ];
		if( a >= 'A' && a <= 'Z' ) a = ( char )( a - 'A' + 'a' );
		if( b >= 'A' && b <= 'Z' ) b = ( char )( b - 'A' + 'a' );
		if( a != b ) return 0;
	}
	return 1;
}

static char* derive_out_path( const char* const in_path, const char* const new_ext )
{
	if( !in_path || !new_ext ) return NULL;
	const char* dot = strrchr( in_path, '.' );
	size_t base_len = dot ? ( size_t )( dot - in_path ) : strlen( in_path );
	size_t ext_len = strlen( new_ext );
	char* out = ( char* ) malloc( base_len + ext_len + 1 );
	if( !out ) return NULL;
	memcpy( out, in_path, base_len );
	memcpy( out + base_len, new_ext, ext_len );
	out[ base_len + ext_len ] = '\0';
	return out;
}

static uint32_t make_color_rgba(uint8_t r, uint8_t g, uint8_t b, uint8_t a){
	return ((uint32_t)r << 24) | ((uint32_t)g << 16) | ((uint32_t)b << 8) | (uint32_t)a;
}

int main(int argc, char** argv){
	if(argc < 2){ print_usage(argv[0]); return 1; }

	// Auto-mode: if first arg is not an option, infer conversion by extension
	if( argv[1][0] != '-' )
	{
		const char* in_path = argv[1];
		const char* out_path = ( argc >= 3 ) ? argv[ 2 ] : NULL;
		if( has_ext_ci( in_path, ".pep" ) )
		{
			if( out_path == NULL )
			{
				char* derived = derive_out_path( in_path, ".bmp" );
				if( !derived ){ fprintf(stderr, "alloc failed\n"); return 1; }
				argv[2] = derived;
				argc = 3;
			}
			else
			{
				argc = 3;
			}
			argv[1] = "--to-bmp";
		}
		else
		{
			if( out_path == NULL )
			{
				char* derived = derive_out_path( in_path, ".pep" );
				if( !derived ){ fprintf(stderr, "alloc failed\n"); return 1; }
				argv[2] = derived;
				argc = 3;
			}
			else
			{
				argc = 3;
			}
			argv[1] = "--image";
		}
	}

	if(strcmp(argv[1], "--demo") == 0){
		if(argc != 3){ print_usage(argv[0]); return 1; }
		const char* out_path = argv[2];
		const uint16_t w = 32, h = 32;
		uint32_t* pixels = (uint32_t*)malloc((size_t)w * h * sizeof(uint32_t));
		if(!pixels){ fprintf(stderr, "alloc failed\n"); return 1; }

		for(uint16_t y=0; y<h; ++y){
			for(uint16_t x=0; x<w; ++x){
				uint8_t r = (uint8_t)(x * 8);
				uint8_t g = (uint8_t)(y * 8);
				uint8_t b = (uint8_t)(((x>>3) ^ (y>>3)) ? 32 : 200);
				pixels[(size_t)y*w + x] = make_color_rgba(r,g,b,255);
			}
		}

		pep p = pep_compress(pixels, w, h, pep_rgba, pep_rgba);
		free(pixels);

		if(p.bytes == NULL || p.bytes_size == 0){
			fprintf(stderr, ".pep compression failed\n");
			return 2;
		}
		if(!pep_save(&p, out_path)){
			fprintf(stderr, "failed to save %s\n", out_path);
			pep_free(&p);
			return 3;
		}
		pep_free(&p);
		printf("Wrote %s (%ux%u)\n", out_path, w, h);
		return 0;
	}

	if(strcmp(argv[1], "--rgba") == 0){
		if(argc != 6){ print_usage(argv[0]); return 1; }
		uint16_t w = (uint16_t)atoi(argv[2]);
		uint16_t h = (uint16_t)atoi(argv[3]);
		const char* in_path = argv[4];
		const char* out_path = argv[5];

		size_t expected = (size_t)w * h * 4u;
		FILE* f = fopen(in_path, "rb");
		if(!f){ fprintf(stderr, "cannot open %s\n", in_path); return 1; }
		fseek(f, 0, SEEK_END);
		long sz = ftell(f);
		fseek(f, 0, SEEK_SET);
		if(sz < 0 || (size_t)sz != expected){
			fprintf(stderr, "input size mismatch: got %ld, expected %zu\n", sz, expected);
			fclose(f);
			return 1;
		}
		uint8_t* raw = (uint8_t*)malloc(expected);
		if(!raw){ fclose(f); fprintf(stderr, "alloc failed\n"); return 1; }
		if(fread(raw, 1, expected, f) != expected){ free(raw); fclose(f); fprintf(stderr, "read failed\n"); return 1; }
		fclose(f);

		uint32_t* pixels = (uint32_t*)malloc((size_t)w * h * sizeof(uint32_t));
		if(!pixels){ free(raw); fprintf(stderr, "alloc failed\n"); return 1; }
		for(size_t i=0;i<(size_t)w*h;i++){
			uint8_t r = raw[i*4+0];
			uint8_t g = raw[i*4+1];
			uint8_t b = raw[i*4+2];
			uint8_t a = raw[i*4+3];
			pixels[i] = make_color_rgba(r,g,b,a);
		}
		free(raw);

		pep p = pep_compress(pixels, w, h, pep_rgba, pep_rgba);
		free(pixels);
		if(p.bytes == NULL || p.bytes_size == 0){ fprintf(stderr, ".pep compression failed\n"); return 2; }
		if(!pep_save(&p, out_path)){ fprintf(stderr, "failed to save %s\n", out_path); pep_free(&p); return 3; }
		pep_free(&p);
		printf("Wrote %s (%ux%u)\n", out_path, w, h);
		return 0;
	}

	if(strcmp(argv[1], "--image") == 0){
		if(argc != 4){ print_usage(argv[0]); return 1; }
		const char* in_png = argv[2];
		const char* out_path = argv[3];

		CFStringRef pathStr = CFStringCreateWithCString(kCFAllocatorDefault, in_png, kCFStringEncodingUTF8);
		if(!pathStr){ fprintf(stderr, "CFStringCreateWithCString failed\n"); return 1; }
		CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, pathStr, kCFURLPOSIXPathStyle, false);
		CFRelease(pathStr);
		if(!url){ fprintf(stderr, "CFURLCreateWithFileSystemPath failed\n"); return 1; }

		CGImageSourceRef src = CGImageSourceCreateWithURL(url, NULL);
		CFRelease(url);
		if(!src){ fprintf(stderr, "CGImageSourceCreateWithURL failed\n"); return 1; }
		CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
		CFRelease(src);
		if(!img){ fprintf(stderr, "CGImageSourceCreateImageAtIndex failed\n"); return 1; }

		size_t w = CGImageGetWidth(img);
		size_t h = CGImageGetHeight(img);
		if(w == 0 || h == 0){ CFRelease(img); fprintf(stderr, "invalid image size\n"); return 1; }

		const size_t bytesPerPixel = 4;
		const size_t bytesPerRow = w * bytesPerPixel;
		uint8_t* raw = (uint8_t*)malloc(h * bytesPerRow);
		if(!raw){ CFRelease(img); fprintf(stderr, "alloc failed\n"); return 1; }

		CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
		CGBitmapInfo info = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault; // RGBA8
		CGContextRef ctx = CGBitmapContextCreate(raw, w, h, 8, bytesPerRow, cs, info);
		CGColorSpaceRelease(cs);
		if(!ctx){ free(raw); CFRelease(img); fprintf(stderr, "CGBitmapContextCreate failed\n"); return 1; }

		CGRect rect = CGRectMake(0, 0, (CGFloat)w, (CGFloat)h);
		CGContextDrawImage(ctx, rect, img);
		CGContextRelease(ctx);
		CFRelease(img);

		// Compress
		uint32_t* pixels = (uint32_t*)malloc(w * h * sizeof(uint32_t));
		if(!pixels){ free(raw); fprintf(stderr, "alloc failed\n"); return 1; }
		for(size_t i=0;i<w*h;i++){
			uint8_t r = raw[i*4+0];
			uint8_t g = raw[i*4+1];
			uint8_t b = raw[i*4+2];
			uint8_t a = raw[i*4+3];
			pixels[i] = make_color_rgba(r,g,b,a);
		}
		free(raw);

		pep p = pep_compress(pixels, (uint16_t)w, (uint16_t)h, pep_rgba, pep_rgba);
		free(pixels);
		if(p.bytes == NULL || p.bytes_size == 0){ fprintf(stderr, ".pep compression failed\n"); return 2; }
		if(!pep_save(&p, out_path)){ fprintf(stderr, "failed to save %s\n", out_path); pep_free(&p); return 3; }
		pep_free(&p);
		printf("Wrote %s (%zux%zu)\n", out_path, w, h);
		return 0;
	}

	if(strcmp(argv[1], "--dry-run") == 0){
		if(argc != 3){ print_usage(argv[0]); return 1; }
		const char* in_png = argv[2];

		CFStringRef pathStr = CFStringCreateWithCString(kCFAllocatorDefault, in_png, kCFStringEncodingUTF8);
		if(!pathStr){ fprintf(stderr, "CFStringCreateWithCString failed\n"); return 1; }
		CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, pathStr, kCFURLPOSIXPathStyle, false);
		CFRelease(pathStr);
		if(!url){ fprintf(stderr, "CFURLCreateWithFileSystemPath failed\n"); return 1; }

		CGImageSourceRef src = CGImageSourceCreateWithURL(url, NULL);
		CFRelease(url);
		if(!src){ fprintf(stderr, "CGImageSourceCreateWithURL failed\n"); return 1; }
		CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
		CFRelease(src);
		if(!img){ fprintf(stderr, "CGImageSourceCreateImageAtIndex failed\n"); return 1; }

		size_t w = CGImageGetWidth(img);
		size_t h = CGImageGetHeight(img);
		if(w == 0 || h == 0){ CFRelease(img); fprintf(stderr, "invalid image size\n"); return 1; }

		const size_t bytesPerPixel = 4;
		const size_t bytesPerRow = w * bytesPerPixel;
		uint8_t* raw = (uint8_t*)malloc(h * bytesPerRow);
		if(!raw){ CFRelease(img); fprintf(stderr, "alloc failed\n"); return 1; }

		CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
		CGBitmapInfo info = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault; // RGBA8
		CGContextRef ctx = CGBitmapContextCreate(raw, w, h, 8, bytesPerRow, cs, info);
		CGColorSpaceRelease(cs);
		if(!ctx){ free(raw); CFRelease(img); fprintf(stderr, "CGBitmapContextCreate failed\n"); return 1; }

		CGRect rect = CGRectMake(0, 0, (CGFloat)w, (CGFloat)h);
		CGContextDrawImage(ctx, rect, img);
		CGContextRelease(ctx);
		CFRelease(img);

		// Compress to memory only (no file I/O)
		uint32_t* pixels = (uint32_t*)malloc(w * h * sizeof(uint32_t));
		if(!pixels){ free(raw); fprintf(stderr, "alloc failed\n"); return 1; }
		for(size_t i=0;i<w*h;i++){
			uint8_t r = raw[i*4+0];
			uint8_t g = raw[i*4+1];
			uint8_t b = raw[i*4+2];
			uint8_t a = raw[i*4+3];
			pixels[i] = make_color_rgba(r,g,b,a);
		}
		free(raw);

		pep p = pep_compress(pixels, (uint16_t)w, (uint16_t)h, pep_rgba, pep_rgba);
		free(pixels);
		if(p.bytes == NULL || p.bytes_size == 0){ fprintf(stderr, ".pep compression failed\n"); return 2; }
		
		// Optionally serialize to get final byte size (still in memory)
		uint32_t serialized_size = 0;
		uint8_t* serialized = pep_serialize(&p, &serialized_size);
		if(serialized){
			free(serialized); // We don't need the actual bytes, just wanted the size
		}
		
		pep_free(&p);
		// Silent success - benchmarking tools don't want output
		return 0;
	}

	if(strcmp(argv[1], "--to-bmp") == 0){
		if(argc != 4){ print_usage(argv[0]); return 1; }
		const char* in_pep = argv[2];
		const char* out_bmp = argv[3];

		pep p = pep_load(in_pep);
		if(p.bytes == NULL || p.bytes_size == 0 || p.width == 0 || p.height == 0){
			fprintf(stderr, "failed to load %s\n", in_pep);
			return 1;
		}
		uint32_t* pixels = pep_decompress(&p, pep_rgba, 0);
		if(!pixels){ pep_free(&p); fprintf(stderr, "decompress failed\n"); return 2; }

		const uint32_t w = p.width;
		const uint32_t h = p.height;
		const uint32_t rowBytes = w * 4u;
		const uint32_t pixelBytes = rowBytes * h;
		const uint32_t fileHeaderSize = 14;
		const uint32_t infoHeaderSize = 40;
		const uint32_t dataOffset = fileHeaderSize + infoHeaderSize;
		const uint32_t fileSize = dataOffset + pixelBytes;

		FILE* f = fopen(out_bmp, "wb");
		if(!f){ free(pixels); pep_free(&p); fprintf(stderr, "cannot write %s\n", out_bmp); return 3; }

		// BITMAPFILEHEADER (14 bytes)
		unsigned char bf[14];
		bf[0] = 'B'; bf[1] = 'M';
		bf[2] = (unsigned char)(fileSize & 0xFF);
		bf[3] = (unsigned char)((fileSize >> 8) & 0xFF);
		bf[4] = (unsigned char)((fileSize >> 16) & 0xFF);
		bf[5] = (unsigned char)((fileSize >> 24) & 0xFF);
		bf[6] = bf[7] = 0; // reserved1
		bf[8] = bf[9] = 0; // reserved2
		bf[10] = (unsigned char)(dataOffset & 0xFF);
		bf[11] = (unsigned char)((dataOffset >> 8) & 0xFF);
		bf[12] = (unsigned char)((dataOffset >> 16) & 0xFF);
		bf[13] = (unsigned char)((dataOffset >> 24) & 0xFF);
		fwrite(bf, 1, 14, f);

		// BITMAPINFOHEADER (40 bytes)
		unsigned char bi[40];
		memset(bi, 0, sizeof(bi));
		bi[0] = 40; // biSize
		bi[4] = (unsigned char)(w & 0xFF);
		bi[5] = (unsigned char)((w >> 8) & 0xFF);
		bi[6] = (unsigned char)((w >> 16) & 0xFF);
		bi[7] = (unsigned char)((w >> 24) & 0xFF);
		// biHeight positive => bottom-up
		bi[8]  = (unsigned char)(h & 0xFF);
		bi[9]  = (unsigned char)((h >> 8) & 0xFF);
		bi[10] = (unsigned char)((h >> 16) & 0xFF);
		bi[11] = (unsigned char)((h >> 24) & 0xFF);
		bi[12] = 1; // planes
		bi[14] = 32; // bitCount
		bi[16] = 0; // BI_RGB (no compression)
		bi[20] = (unsigned char)(pixelBytes & 0xFF);
		bi[21] = (unsigned char)((pixelBytes >> 8) & 0xFF);
		bi[22] = (unsigned char)((pixelBytes >> 16) & 0xFF);
		bi[23] = (unsigned char)((pixelBytes >> 24) & 0xFF);
		// 72 DPI ≈ 2835 pixels/meter
		const uint32_t ppm = 2835;
		bi[24] = (unsigned char)(ppm & 0xFF);
		bi[25] = (unsigned char)((ppm >> 8) & 0xFF);
		bi[26] = (unsigned char)((ppm >> 16) & 0xFF);
		bi[27] = (unsigned char)((ppm >> 24) & 0xFF);
		bi[28] = (unsigned char)(ppm & 0xFF);
		bi[29] = (unsigned char)((ppm >> 8) & 0xFF);
		bi[30] = (unsigned char)((ppm >> 16) & 0xFF);
		bi[31] = (unsigned char)((ppm >> 24) & 0xFF);
		fwrite(bi, 1, 40, f);

		// Pixel data bottom-up, emit BGRA bytes explicitly from RGBA value
		unsigned char* tmpRow = (unsigned char*)malloc(rowBytes);
		if(!tmpRow){ fclose(f); free(pixels); pep_free(&p); fprintf(stderr, "alloc failed\n"); return 4; }
		for(int y = (int)h - 1; y >= 0; --y){
			for(uint32_t x = 0; x < w; ++x){
				uint32_t v = pixels[(size_t)y * w + x]; // RGBA in bits 24..0
				unsigned char r = (unsigned char)((v >> 24) & 0xFF);
				unsigned char g = (unsigned char)((v >> 16) & 0xFF);
				unsigned char b = (unsigned char)((v >> 8) & 0xFF);
				unsigned char a = (unsigned char)(v & 0xFF);
				tmpRow[x*4+0] = b;
				tmpRow[x*4+1] = g;
				tmpRow[x*4+2] = r;
				tmpRow[x*4+3] = a;
			}
			fwrite(tmpRow, 1, rowBytes, f);
		}
		free(tmpRow);

		fclose(f);
		free(pixels);
		pep_free(&p);
		printf("Wrote %s (%ux%u 32bpp BGRA)\n", out_bmp, w, h);
		return 0;
	}

	if(strcmp(argv[1], "--to-rle-bmp") == 0){
		if(argc != 4){ print_usage(argv[0]); return 1; }
		const char* in_pep = argv[2];
		const char* out_rle = argv[3];

		pep p = pep_load(in_pep);
		if(p.bytes == NULL || p.bytes_size == 0 || p.width == 0 || p.height == 0){
			fprintf(stderr, "failed to load %s\n", in_pep);
			return 1;
		}

		// Decompress in original stored format so pixels match palette entries
		uint32_t* pixels = pep_decompress(&p, p.format, 0);
		if(!pixels){ pep_free(&p); fprintf(stderr, "decompress failed\n"); return 2; }

		const uint32_t w = p.width;
		const uint32_t h = p.height;
		const uint8_t palette_size = p.palette_size ? p.palette_size : 1;
		if(palette_size > 255){ free(pixels); pep_free(&p); fprintf(stderr, "palette too large for 8-bit BMP\n"); return 3; }

		// Map RGBA values (in p.format order) to palette indices
		// Linear search per pixel; acceptable for our use-case
		uint8_t* indices = (uint8_t*)malloc((size_t)w * h);
		if(!indices){ free(pixels); pep_free(&p); fprintf(stderr, "alloc failed\n"); return 4; }
		for(uint32_t i = 0; i < w * h; ++i){
			uint32_t px = pixels[i];
			uint16_t idx = 0;
			while(idx < palette_size && p.palette[idx] != px) idx++;
			if(idx >= palette_size) idx = 0; // fallback
			indices[i] = (uint8_t)idx;
		}

		// Prepare RLE8 encoding buffer (worst-case ~2x + control codes)
		size_t cap = (size_t)w * h * 2u + (size_t)h * 2u + 2u;
		uint8_t* rle = (uint8_t*)malloc(cap);
		if(!rle){ free(indices); free(pixels); pep_free(&p); fprintf(stderr, "alloc failed\n"); return 5; }
		size_t rle_size = 0;
		#define EMIT8(B) do { if(rle_size >= cap){ cap = cap * 2u + 1024u; rle = (uint8_t*)realloc(rle, cap); if(!rle){ fprintf(stderr, "alloc failed\n"); free(indices); free(pixels); pep_free(&p); return 6; } } rle[rle_size++] = (uint8_t)(B); } while(0)

		// Encode bottom-up
		for(int yy = (int)h - 1; yy >= 0; --yy){
			const uint8_t* row = indices + (size_t)yy * w;
			uint32_t x = 0;
			while(x < w){
				// Find run length
				uint8_t val = row[x];
				uint32_t run = 1;
				while(x + run < w && row[x + run] == val && run < 255) run++;
				if(run >= 3){
					// Emit runs possibly in chunks of 255
					uint32_t rem = run;
					while(rem > 0){
						uint8_t chunk = (uint8_t)((rem > 255) ? 255 : rem);
						EMIT8(chunk); EMIT8(val);
						rem -= chunk;
					}
					x += run;
				}else{
					// Absolute mode: collect until next long run or row end, max 255
					uint32_t start = x;
					uint32_t count = 0;
					while(x < w && count < 255){
						// If a run of 3+ starts here, stop literals
						if(x + 2 < w && row[x] == row[x+1] && row[x] == row[x+2]) break;
						x++; count++;
					}
					EMIT8(0); EMIT8((uint8_t)count);
					for(uint32_t i = 0; i < count; ++i) EMIT8(row[start + i]);
					if(count & 1) EMIT8(0); // pad to word
				}
			}
			// End of line
			EMIT8(0); EMIT8(0);
		}
		// End of bitmap
		EMIT8(0); EMIT8(1);

		#undef EMIT8

		// Compute headers
		const uint32_t fileHeaderSize = 14;
		const uint32_t infoHeaderSize = 40;
		const uint32_t paletteBytes = (uint32_t)palette_size * 4u;
		const uint32_t dataOffset = fileHeaderSize + infoHeaderSize + paletteBytes;
		const uint32_t fileSize = dataOffset + (uint32_t)rle_size;

		FILE* f = fopen(out_rle, "wb");
		if(!f){ free(rle); free(indices); free(pixels); pep_free(&p); fprintf(stderr, "cannot write %s\n", out_rle); return 7; }

		// BITMAPFILEHEADER
		unsigned char bf[14];
		bf[0] = 'B'; bf[1] = 'M';
		bf[2] = (unsigned char)(fileSize & 0xFF);
		bf[3] = (unsigned char)((fileSize >> 8) & 0xFF);
		bf[4] = (unsigned char)((fileSize >> 16) & 0xFF);
		bf[5] = (unsigned char)((fileSize >> 24) & 0xFF);
		bf[6] = bf[7] = 0; // reserved1
		bf[8] = bf[9] = 0; // reserved2
		bf[10] = (unsigned char)(dataOffset & 0xFF);
		bf[11] = (unsigned char)((dataOffset >> 8) & 0xFF);
		bf[12] = (unsigned char)((dataOffset >> 16) & 0xFF);
		bf[13] = (unsigned char)((dataOffset >> 24) & 0xFF);
		fwrite(bf, 1, 14, f);

		// BITMAPINFOHEADER
		unsigned char bi[40];
		memset(bi, 0, sizeof(bi));
		bi[0] = 40; // biSize
		bi[4] = (unsigned char)(w & 0xFF);
		bi[5] = (unsigned char)((w >> 8) & 0xFF);
		bi[6] = (unsigned char)((w >> 16) & 0xFF);
		bi[7] = (unsigned char)((w >> 24) & 0xFF);
		bi[8]  = (unsigned char)(h & 0xFF);
		bi[9]  = (unsigned char)((h >> 8) & 0xFF);
		bi[10] = (unsigned char)((h >> 16) & 0xFF);
		bi[11] = (unsigned char)((h >> 24) & 0xFF);
		bi[12] = 1; // planes
		bi[14] = 8; // bitCount
		bi[16] = 1; // BI_RLE8
		bi[20] = (unsigned char)(rle_size & 0xFF);
		bi[21] = (unsigned char)((rle_size >> 8) & 0xFF);
		bi[22] = (unsigned char)((rle_size >> 16) & 0xFF);
		bi[23] = (unsigned char)((rle_size >> 24) & 0xFF);
		// 72 DPI ≈ 2835 pixels/meter
		const uint32_t ppm = 2835;
		bi[24] = (unsigned char)(ppm & 0xFF);
		bi[25] = (unsigned char)((ppm >> 8) & 0xFF);
		bi[26] = (unsigned char)((ppm >> 16) & 0xFF);
		bi[27] = (unsigned char)((ppm >> 24) & 0xFF);
		bi[28] = (unsigned char)(ppm & 0xFF);
		bi[29] = (unsigned char)((ppm >> 8) & 0xFF);
		bi[30] = (unsigned char)((ppm >> 16) & 0xFF);
		bi[31] = (unsigned char)((ppm >> 24) & 0xFF);
		// biClrUsed
		bi[32] = (unsigned char)(palette_size & 0xFF);
		bi[33] = (unsigned char)((palette_size >> 8) & 0xFF);
		bi[34] = 0;
		bi[35] = 0;
		fwrite(bi, 1, 40, f);

		// Palette (B,G,R,0)
		for(uint32_t i = 0; i < palette_size; ++i){
			uint32_t c = p.palette[i];
			unsigned char r, g, b;
			switch(p.format){
				case pep_rgba: r = (unsigned char)((c >> 24) & 0xFF); g = (unsigned char)((c >> 16) & 0xFF); b = (unsigned char)((c >> 8) & 0xFF); break;
				case pep_bgra: b = (unsigned char)((c >> 24) & 0xFF); g = (unsigned char)((c >> 16) & 0xFF); r = (unsigned char)((c >> 8) & 0xFF); break;
				case pep_abgr: b = (unsigned char)((c >> 16) & 0xFF); g = (unsigned char)((c >> 8) & 0xFF); r = (unsigned char)(c & 0xFF); break;
				case pep_argb: r = (unsigned char)((c >> 16) & 0xFF); g = (unsigned char)((c >> 8) & 0xFF); b = (unsigned char)(c & 0xFF); break;
				default: r = (unsigned char)((c >> 24) & 0xFF); g = (unsigned char)((c >> 16) & 0xFF); b = (unsigned char)((c >> 8) & 0xFF); break;
			}
			unsigned char pe[4] = { b, g, r, 0 };
			fwrite(pe, 1, 4, f);
		}

		// Pixel data (RLE8)
		fwrite(rle, 1, rle_size, f);

		fclose(f);
		free(rle);
		free(indices);
		free(pixels);
		pep_free(&p);
		printf("Wrote %s (%ux%u 8bpp RLE)\n", out_rle, w, h);
		return 0;
	}

	print_usage(argv[0]);
	return 1;
}
