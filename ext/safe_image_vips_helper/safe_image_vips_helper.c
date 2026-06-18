#include <errno.h>
#include <fcntl.h>
#include <glib.h>
#include <math.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>
#include <vips/vips.h>

#define DEFAULT_MAX_PIXELS (128LL * 1024LL * 1024LL)
#define DEFAULT_JPEG_QUALITY 85
#define DEFAULT_NATIVE_CONVERT_JPEG_QUALITY 92

typedef struct {
  const char *key;
  const char *value;
} option_t;

typedef struct {
  option_t items[64];
  int count;
} options_t;

static double now_ms(void) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (double)tv.tv_sec * 1000.0 + (double)tv.tv_usec / 1000.0;
}

static const char *opt(options_t *opts, const char *key) {
  for (int i = 0; i < opts->count; i++) {
    if (strcmp(opts->items[i].key, key) == 0) {
      return opts->items[i].value;
    }
  }
  return NULL;
}

static const char *opt_required(options_t *opts, const char *key) {
  const char *value = opt(opts, key);
  if (!value || value[0] == '\0') {
    fprintf(stderr, "missing required option --%s\n", key);
    exit(2);
  }
  return value;
}

static int opt_int(options_t *opts, const char *key, int fallback) {
  const char *value = opt(opts, key);
  if (!value) {
    return fallback;
  }
  char *end = NULL;
  long parsed = strtol(value, &end, 10);
  if (!end || *end != '\0') {
    fprintf(stderr, "invalid integer for --%s\n", key);
    exit(2);
  }
  return (int)parsed;
}

static long long opt_ll(options_t *opts, const char *key, long long fallback) {
  const char *value = opt(opts, key);
  if (!value) {
    return fallback;
  }
  char *end = NULL;
  long long parsed = strtoll(value, &end, 10);
  if (!end || *end != '\0' || parsed <= 0) {
    fprintf(stderr, "invalid positive integer for --%s\n", key);
    exit(2);
  }
  return parsed;
}

static double opt_double(options_t *opts, const char *key, double fallback) {
  const char *value = opt(opts, key);
  if (!value) {
    return fallback;
  }
  char *end = NULL;
  double parsed = strtod(value, &end);
  if (!end || *end != '\0' || !isfinite(parsed)) {
    fprintf(stderr, "invalid number for --%s\n", key);
    exit(2);
  }
  return parsed;
}

static void parse_options(int argc, char **argv, options_t *opts) {
  opts->count = 0;
  for (int i = 2; i < argc; i++) {
    if (strncmp(argv[i], "--", 2) != 0) {
      fprintf(stderr, "unexpected argument: %s\n", argv[i]);
      exit(2);
    }
    if (i + 1 >= argc) {
      fprintf(stderr, "missing value for %s\n", argv[i]);
      exit(2);
    }
    if (opts->count >= 64) {
      fprintf(stderr, "too many options\n");
      exit(2);
    }
    opts->items[opts->count].key = argv[i] + 2;
    opts->items[opts->count].value = argv[++i];
    opts->count++;
  }
}

static void json_string(FILE *f, const char *s) {
  fputc('"', f);
  for (const unsigned char *p = (const unsigned char *)s; p && *p; p++) {
    switch (*p) {
    case '"':
      fputs("\\\"", f);
      break;
    case '\\':
      fputs("\\\\", f);
      break;
    case '\b':
      fputs("\\b", f);
      break;
    case '\f':
      fputs("\\f", f);
      break;
    case '\n':
      fputs("\\n", f);
      break;
    case '\r':
      fputs("\\r", f);
      break;
    case '\t':
      fputs("\\t", f);
      break;
    default:
      if (*p < 0x20) {
        fprintf(f, "\\u%04x", *p);
      } else {
        fputc(*p, f);
      }
    }
  }
  fputc('"', f);
}

static void write_error(const char *response, const char *klass, const char *message) {
  FILE *f = fopen(response, "w");
  if (!f) {
    return;
  }
  fputs("{\"ok\":false,\"error\":", f);
  json_string(f, klass);
  fputs(",\"message\":", f);
  json_string(f, message ? message : "error");
  fputs("}\n", f);
  fclose(f);
}

static void write_info(const char *response, const char *input_format, const char *output_format,
                       int width, int height, double duration_ms) {
  FILE *f = fopen(response, "w");
  if (!f) {
    fprintf(stderr, "could not write response: %s\n", strerror(errno));
    exit(1);
  }
  fputs("{\"ok\":true", f);
  if (input_format) {
    fputs(",\"input_format\":", f);
    json_string(f, input_format);
  }
  if (output_format) {
    fputs(",\"output_format\":", f);
    json_string(f, output_format);
  }
  fprintf(f, ",\"width\":%d,\"height\":%d,\"duration_ms\":%.3f}\n", width, height, duration_ms);
  fclose(f);
}

static void write_value_int(const char *response, int value) {
  FILE *f = fopen(response, "w");
  if (!f) {
    exit(1);
  }
  fprintf(f, "{\"ok\":true,\"value\":%d}\n", value);
  fclose(f);
}

static void write_value_string(const char *response, const char *value) {
  FILE *f = fopen(response, "w");
  if (!f) {
    exit(1);
  }
  fputs("{\"ok\":true,\"value\":", f);
  json_string(f, value);
  fputs("}\n", f);
  fclose(f);
}

static const char *extname(const char *path) {
  const char *dot = strrchr(path, '.');
  return dot ? dot + 1 : "";
}

static const char *normalized_format(const char *format) {
  if (!format) {
    return NULL;
  }
  if (g_ascii_strcasecmp(format, "jpg") == 0 || g_ascii_strcasecmp(format, "jpeg") == 0) {
    return "jpg";
  }
  if (g_ascii_strcasecmp(format, "png") == 0) {
    return "png";
  }
  if (g_ascii_strcasecmp(format, "webp") == 0) {
    return "webp";
  }
  if (g_ascii_strcasecmp(format, "gif") == 0) {
    return "gif";
  }
  if (g_ascii_strcasecmp(format, "heic") == 0 || g_ascii_strcasecmp(format, "heif") == 0) {
    return "heic";
  }
  if (g_ascii_strcasecmp(format, "avif") == 0) {
    return "avif";
  }
  if (g_ascii_strcasecmp(format, "jxl") == 0) {
    return "jxl";
  }
  return NULL;
}

static int load_image_from_source(VipsSource *source, const char *format, VipsImage **out) {
  if (strcmp(format, "jpg") == 0) {
    return vips_jpegload_source(source, out, "access", VIPS_ACCESS_SEQUENTIAL, "fail-on",
                                VIPS_FAIL_ON_ERROR, NULL);
  }
  if (strcmp(format, "png") == 0) {
    return vips_pngload_source(source, out, "access", VIPS_ACCESS_SEQUENTIAL, "fail-on",
                               VIPS_FAIL_ON_ERROR, NULL);
  }
  if (strcmp(format, "webp") == 0) {
    return vips_webpload_source(source, out, "access", VIPS_ACCESS_SEQUENTIAL, "fail-on",
                                VIPS_FAIL_ON_ERROR, NULL);
  }
  if (strcmp(format, "gif") == 0) {
    return vips_gifload_source(source, out, "access", VIPS_ACCESS_SEQUENTIAL, "fail-on",
                               VIPS_FAIL_ON_ERROR, NULL);
  }
  if (strcmp(format, "heic") == 0 || strcmp(format, "avif") == 0) {
    return vips_heifload_source(source, out, "access", VIPS_ACCESS_SEQUENTIAL, "fail-on",
                                VIPS_FAIL_ON_ERROR, NULL);
  }
  if (strcmp(format, "jxl") == 0) {
    return vips_jxlload_source(source, out, "access", VIPS_ACCESS_SEQUENTIAL, "fail-on",
                               VIPS_FAIL_ON_ERROR, NULL);
  }
  vips_error("safe_image", "%s", "unsupported input format");
  return -1;
}

static int load_image(const char *path, gboolean autorotate, VipsImage **out,
                      const char **format_out) {
  const char *format = normalized_format(extname(path));
  if (!format) {
    vips_error("safe_image", "%s", "unsupported input format");
    return -1;
  }
  int rc = -1;
  if (strcmp(format, "jpg") == 0) {
    rc = vips_jpegload(path, out, "access", VIPS_ACCESS_SEQUENTIAL, "fail-on", VIPS_FAIL_ON_ERROR,
                       NULL);
  } else if (strcmp(format, "png") == 0) {
    rc = vips_pngload(path, out, "access", VIPS_ACCESS_SEQUENTIAL, "fail-on", VIPS_FAIL_ON_ERROR,
                      NULL);
  } else if (strcmp(format, "webp") == 0) {
    rc = vips_webpload(path, out, "access", VIPS_ACCESS_SEQUENTIAL, "fail-on", VIPS_FAIL_ON_ERROR,
                       NULL);
  } else if (strcmp(format, "gif") == 0) {
    rc = vips_gifload(path, out, "access", VIPS_ACCESS_SEQUENTIAL, "fail-on", VIPS_FAIL_ON_ERROR,
                      NULL);
  } else if (strcmp(format, "heic") == 0 || strcmp(format, "avif") == 0) {
    rc = vips_heifload(path, out, "access", VIPS_ACCESS_SEQUENTIAL, "fail-on", VIPS_FAIL_ON_ERROR,
                       NULL);
  } else if (strcmp(format, "jxl") == 0) {
    rc = vips_jxlload(path, out, "access", VIPS_ACCESS_SEQUENTIAL, "fail-on", VIPS_FAIL_ON_ERROR,
                      NULL);
  }
  if (rc != 0) {
    return rc;
  }
  if (autorotate && vips_image_get_orientation(*out) > 1) {
    VIPS_UNREF(*out);
    if (strcmp(format, "jpg") == 0) {
      rc = vips_jpegload(path, out, "access", VIPS_ACCESS_RANDOM, "fail-on", VIPS_FAIL_ON_ERROR,
                         NULL);
    } else if (strcmp(format, "png") == 0) {
      rc = vips_pngload(path, out, "access", VIPS_ACCESS_RANDOM, "fail-on", VIPS_FAIL_ON_ERROR,
                        NULL);
    } else if (strcmp(format, "webp") == 0) {
      rc = vips_webpload(path, out, "access", VIPS_ACCESS_RANDOM, "fail-on", VIPS_FAIL_ON_ERROR,
                         NULL);
    } else if (strcmp(format, "gif") == 0) {
      rc = vips_gifload(path, out, "access", VIPS_ACCESS_RANDOM, "fail-on", VIPS_FAIL_ON_ERROR,
                        NULL);
    } else if (strcmp(format, "heic") == 0 || strcmp(format, "avif") == 0) {
      rc = vips_heifload(path, out, "access", VIPS_ACCESS_RANDOM, "fail-on", VIPS_FAIL_ON_ERROR,
                         NULL);
    } else if (strcmp(format, "jxl") == 0) {
      rc = vips_jxlload(path, out, "access", VIPS_ACCESS_RANDOM, "fail-on", VIPS_FAIL_ON_ERROR,
                        NULL);
    }
    if (rc != 0) {
      return rc;
    }
  }
  *format_out = format;
  return 0;
}

static int check_pixels(VipsImage *image, long long max_pixels) {
  int width = vips_image_get_width(image);
  int height = vips_image_get_height(image);
  if (width <= 0 || height <= 0) {
    vips_error("safe_image", "%s", "image dimensions are invalid");
    return -2;
  }
  long long pixels = (long long)width * (long long)height;
  if (pixels > max_pixels) {
    vips_error("safe_image", "image has %lld pixels, exceeds %lld", pixels, max_pixels);
    return -3;
  }
  return 0;
}

static int save_image(VipsImage *image, const char *path, const char *format, int quality) {
  if (strcmp(format, "jpg") == 0) {
    return vips_jpegsave(image, path, "Q", quality, "interlace", FALSE, "strip", TRUE, NULL);
  }
  if (strcmp(format, "png") == 0) {
    return vips_pngsave(image, path, "compression", 6, "strip", TRUE, NULL);
  }
  if (strcmp(format, "webp") == 0) {
    return vips_webpsave(image, path, "Q", quality, "strip", TRUE, NULL);
  }
  if (strcmp(format, "avif") == 0) {
    return vips_heifsave(image, path, "Q", quality, "compression",
                         VIPS_FOREIGN_HEIF_COMPRESSION_AV1, "strip", TRUE, NULL);
  }
  if (strcmp(format, "gif") == 0) {
    return vips_gifsave(image, path, "strip", TRUE, NULL);
  }
  if (strcmp(format, "jxl") == 0) {
    return vips_jxlsave(image, path, "Q", quality, "strip", TRUE, NULL);
  }
  vips_error("safe_image", "%s", "unsupported output format");
  return -1;
}

static int init_vips(const char *argv0) {
  if (VIPS_INIT(argv0)) {
    return -1;
  }
  if (vips_version(0) < 8 || (vips_version(0) == 8 && vips_version(1) < 13)) {
    vips_error("safe_image", "libvips >= 8.13 is required (found %d.%d)", vips_version(0),
               vips_version(1));
    return -1;
  }
  vips_block_untrusted_set(TRUE);
  vips_operation_block_set("VipsForeignLoadMagick", TRUE);
  vips_operation_block_set("VipsForeignLoadMagick6", TRUE);
  vips_operation_block_set("VipsForeignLoadMagick7", TRUE);
  vips_operation_block_set("VipsForeignLoadJxl", FALSE);
  vips_operation_block_set("VipsForeignSaveJxl", FALSE);
  vips_concurrency_set(1);
  vips_cache_set_max(0);
  vips_cache_set_max_mem(0);
  vips_cache_set_max_files(0);
  return 0;
}

static void fail_response(const char *response, const char *klass) {
  const char *msg = vips_error_buffer();
  write_error(response, klass, msg && msg[0] ? msg : "libvips error");
}

static int cmd_probe(options_t *opts, double started) {
  const char *response = opt_required(opts, "response");
  const char *input = opt_required(opts, "input");
  long long max_pixels = opt_ll(opts, "max-pixels", DEFAULT_MAX_PIXELS);
  VipsImage *image = NULL;
  const char *format = NULL;
  if (load_image(input, FALSE, &image, &format) != 0) {
    fail_response(response, "InvalidImageError");
    return 1;
  }
  int check = check_pixels(image, max_pixels);
  if (check != 0) {
    fail_response(response, check == -3 ? "LimitError" : "InvalidImageError");
    VIPS_UNREF(image);
    return 1;
  }
  write_info(response, format, NULL, vips_image_get_width(image), vips_image_get_height(image),
             now_ms() - started);
  VIPS_UNREF(image);
  return 0;
}

static int cmd_orientation(options_t *opts) {
  const char *response = opt_required(opts, "response");
  const char *input = opt_required(opts, "input");
  long long max_pixels = opt_ll(opts, "max-pixels", DEFAULT_MAX_PIXELS);
  VipsImage *image = NULL;
  const char *format = NULL;
  if (load_image(input, FALSE, &image, &format) != 0) {
    fail_response(response, "InvalidImageError");
    return 1;
  }
  int check = check_pixels(image, max_pixels);
  if (check != 0) {
    fail_response(response, check == -3 ? "LimitError" : "InvalidImageError");
    VIPS_UNREF(image);
    return 1;
  }
  int value = vips_image_get_orientation(image);
  if (value < 1 || value > 8) {
    value = 1;
  }
  write_value_int(response, value);
  VIPS_UNREF(image);
  return 0;
}

static int cmd_pages(options_t *opts) {
  const char *response = opt_required(opts, "response");
  const char *input = opt_required(opts, "input");
  long long max_pixels = opt_ll(opts, "max-pixels", DEFAULT_MAX_PIXELS);
  VipsImage *image = NULL;
  const char *format = NULL;
  if (load_image(input, FALSE, &image, &format) != 0) {
    fail_response(response, "InvalidImageError");
    return 1;
  }
  int check = check_pixels(image, max_pixels);
  if (check != 0) {
    fail_response(response, check == -3 ? "LimitError" : "InvalidImageError");
    VIPS_UNREF(image);
    return 1;
  }
  write_value_int(response, vips_image_get_n_pages(image));
  VIPS_UNREF(image);
  return 0;
}

static int cmd_thumbnail(options_t *opts, double started) {
  const char *response = opt_required(opts, "response");
  const char *input = opt_required(opts, "input");
  const char *output = opt_required(opts, "output");
  int width = opt_int(opts, "width", 0);
  int height = opt_int(opts, "height", 0);
  int quality = opt_int(opts, "quality", DEFAULT_JPEG_QUALITY);
  const char *out_format = normalized_format(opt_required(opts, "format"));
  const char *in_format = normalized_format(extname(input));
  long long max_pixels = opt_ll(opts, "max-pixels", DEFAULT_MAX_PIXELS);
  if (width <= 0 || height <= 0 || quality < 1 || quality > 100 || !out_format ||
      strcmp(out_format, "heic") == 0 || !in_format) {
    write_error(response, "ArgumentError", "invalid thumbnail arguments");
    return 1;
  }

  int fd = open(input, O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    write_error(response, "InvalidImageError", strerror(errno));
    return 1;
  }

  VipsImage *image = NULL, *thumb = NULL;
  int header_fd = dup(fd);
  if (header_fd < 0) {
    close(fd);
    write_error(response, "InvalidImageError", strerror(errno));
    return 1;
  }
  VipsSource *header_source = vips_source_new_from_descriptor(header_fd);
  if (!header_source || load_image_from_source(header_source, in_format, &image) != 0) {
    if (header_source) {
      g_object_unref(header_source);
    } else {
      close(header_fd);
    }
    close(fd);
    fail_response(response, "InvalidImageError");
    return 1;
  }
  g_object_unref(header_source);
  int check = check_pixels(image, max_pixels);
  VIPS_UNREF(image);
  if (check != 0) {
    close(fd);
    fail_response(response, check == -3 ? "LimitError" : "InvalidImageError");
    return 1;
  }

  if (lseek(fd, 0, SEEK_SET) < 0) {
    close(fd);
    write_error(response, "InvalidImageError", strerror(errno));
    return 1;
  }
  int thumb_fd = dup(fd);
  close(fd);
  if (thumb_fd < 0) {
    write_error(response, "InvalidImageError", strerror(errno));
    return 1;
  }
  VipsSource *thumb_source = vips_source_new_from_descriptor(thumb_fd);
  if (!thumb_source ||
      vips_thumbnail_source(thumb_source, &thumb, width, "height", height, "size", VIPS_SIZE_BOTH,
                            "crop", VIPS_INTERESTING_CENTRE, "fail-on", VIPS_FAIL_ON_ERROR,
                            NULL) != 0 ||
      save_image(thumb, output, out_format, quality) != 0) {
    if (thumb_source) {
      g_object_unref(thumb_source);
    } else {
      close(thumb_fd);
    }
    fail_response(response, "InvalidImageError");
    VIPS_UNREF(thumb);
    return 1;
  }
  g_object_unref(thumb_source);
  write_info(response, in_format, out_format, vips_image_get_width(thumb),
             vips_image_get_height(thumb), now_ms() - started);
  VIPS_UNREF(thumb);
  return 0;
}

static int cmd_resize(options_t *opts, double started) {
  const char *response = opt_required(opts, "response");
  const char *input = opt_required(opts, "input");
  const char *output = opt_required(opts, "output");
  double scale = opt_double(opts, "scale", 0.0);
  int quality = opt_int(opts, "quality", DEFAULT_JPEG_QUALITY);
  const char *out_format = normalized_format(opt_required(opts, "format"));
  long long max_pixels = opt_ll(opts, "max-pixels", DEFAULT_MAX_PIXELS);
  if (scale <= 0.0 || scale > 100.0 || quality < 1 || quality > 100 || !out_format ||
      strcmp(out_format, "heic") == 0) {
    write_error(response, "ArgumentError", "invalid resize arguments");
    return 1;
  }
  VipsImage *image = NULL, *rot = NULL, *resized = NULL;
  const char *in_format = NULL;
  if (load_image(input, TRUE, &image, &in_format) != 0) {
    fail_response(response, "InvalidImageError");
    return 1;
  }
  int check = check_pixels(image, max_pixels);
  if (check != 0) {
    fail_response(response, check == -3 ? "LimitError" : "InvalidImageError");
    VIPS_UNREF(image);
    return 1;
  }
  if (vips_autorot(image, &rot, NULL) != 0 || vips_resize(rot, &resized, scale, NULL) != 0 ||
      save_image(resized, output, out_format, quality) != 0) {
    fail_response(response, "InvalidImageError");
    VIPS_UNREF(image);
    VIPS_UNREF(rot);
    VIPS_UNREF(resized);
    return 1;
  }
  write_info(response, in_format, out_format, vips_image_get_width(resized),
             vips_image_get_height(resized), now_ms() - started);
  VIPS_UNREF(image);
  VIPS_UNREF(rot);
  VIPS_UNREF(resized);
  return 0;
}

static int cmd_crop_north(options_t *opts, double started) {
  const char *response = opt_required(opts, "response");
  const char *input = opt_required(opts, "input");
  const char *output = opt_required(opts, "output");
  int width = opt_int(opts, "width", 0), height = opt_int(opts, "height", 0),
      quality = opt_int(opts, "quality", DEFAULT_JPEG_QUALITY);
  const char *out_format = normalized_format(opt_required(opts, "format"));
  long long max_pixels = opt_ll(opts, "max-pixels", DEFAULT_MAX_PIXELS);
  if (width <= 0 || height <= 0 || quality < 1 || quality > 100 || !out_format ||
      strcmp(out_format, "heic") == 0) {
    write_error(response, "ArgumentError", "invalid crop arguments");
    return 1;
  }
  VipsImage *image = NULL, *rot = NULL, *resized = NULL, *cropped = NULL;
  const char *in_format = NULL;
  if (load_image(input, TRUE, &image, &in_format) != 0) {
    fail_response(response, "InvalidImageError");
    return 1;
  }
  int check = check_pixels(image, max_pixels);
  if (check != 0) {
    fail_response(response, check == -3 ? "LimitError" : "InvalidImageError");
    VIPS_UNREF(image);
    return 1;
  }
  if (vips_autorot(image, &rot, NULL) != 0) {
    fail_response(response, "InvalidImageError");
    VIPS_UNREF(image);
    return 1;
  }
  double scale =
      fmax((double)width / vips_image_get_width(rot), (double)height / vips_image_get_height(rot)) *
      1.0000001;
  int left;
  if (vips_resize(rot, &resized, scale, NULL) != 0) {
    fail_response(response, "InvalidImageError");
    VIPS_UNREF(image);
    VIPS_UNREF(rot);
    return 1;
  }
  left = (vips_image_get_width(resized) - width) / 2;
  if (left < 0) {
    left = 0;
  }
  if (vips_extract_area(resized, &cropped, left, 0, width, height, NULL) != 0 ||
      save_image(cropped, output, out_format, quality) != 0) {
    fail_response(response, "InvalidImageError");
    VIPS_UNREF(image);
    VIPS_UNREF(rot);
    VIPS_UNREF(resized);
    VIPS_UNREF(cropped);
    return 1;
  }
  write_info(response, in_format, out_format, vips_image_get_width(cropped),
             vips_image_get_height(cropped), now_ms() - started);
  VIPS_UNREF(image);
  VIPS_UNREF(rot);
  VIPS_UNREF(resized);
  VIPS_UNREF(cropped);
  return 0;
}

static int cmd_convert(options_t *opts, double started) {
  const char *response = opt_required(opts, "response");
  const char *input = opt_required(opts, "input");
  const char *output = opt_required(opts, "output");
  int quality = opt_int(opts, "quality", DEFAULT_NATIVE_CONVERT_JPEG_QUALITY);
  const char *out_format = normalized_format(opt_required(opts, "format"));
  long long max_pixels = opt_ll(opts, "max-pixels", DEFAULT_MAX_PIXELS);
  if (quality < 1 || quality > 100 || !out_format || strcmp(out_format, "heic") == 0) {
    write_error(response, "ArgumentError", "invalid convert arguments");
    return 1;
  }
  VipsImage *image = NULL, *rot = NULL, *final = NULL;
  const char *in_format = NULL;
  if (load_image(input, TRUE, &image, &in_format) != 0) {
    fail_response(response, "InvalidImageError");
    return 1;
  }
  int check = check_pixels(image, max_pixels);
  if (check != 0) {
    fail_response(response, check == -3 ? "LimitError" : "InvalidImageError");
    VIPS_UNREF(image);
    return 1;
  }
  if (vips_autorot(image, &rot, NULL) != 0) {
    fail_response(response, "InvalidImageError");
    VIPS_UNREF(image);
    return 1;
  }
  if (strcmp(out_format, "jpg") == 0 && vips_image_hasalpha(rot)) {
    double bg[3] = {255.0, 255.0, 255.0};
    VipsArrayDouble *arr = vips_array_double_new(bg, 3);
    if (vips_flatten(rot, &final, "background", arr, NULL) != 0) {
      vips_area_unref((VipsArea *)arr);
      fail_response(response, "InvalidImageError");
      VIPS_UNREF(image);
      VIPS_UNREF(rot);
      return 1;
    }
    vips_area_unref((VipsArea *)arr);
  } else {
    final = rot;
    g_object_ref(final);
  }
  if (save_image(final, output, out_format, quality) != 0) {
    fail_response(response, "InvalidImageError");
    VIPS_UNREF(image);
    VIPS_UNREF(rot);
    VIPS_UNREF(final);
    return 1;
  }
  write_info(response, in_format, out_format, vips_image_get_width(final),
             vips_image_get_height(final), now_ms() - started);
  VIPS_UNREF(image);
  VIPS_UNREF(rot);
  VIPS_UNREF(final);
  return 0;
}

static int cmd_dominant_color(options_t *opts) {
  const char *response = opt_required(opts, "response");
  const char *input = opt_required(opts, "input");
  long long max_pixels = opt_ll(opts, "max-pixels", DEFAULT_MAX_PIXELS);
  VipsImage *image = NULL, *srgb = NULL, *work = NULL, *stats = NULL;
  const char *format = NULL;
  if (load_image(input, FALSE, &image, &format) != 0) {
    fail_response(response, "InvalidImageError");
    return 1;
  }
  int check = check_pixels(image, max_pixels);
  if (check != 0) {
    fail_response(response, check == -3 ? "LimitError" : "InvalidImageError");
    VIPS_UNREF(image);
    return 1;
  }
  if (vips_colourspace_issupported(image)) {
    if (vips_colourspace(image, &srgb, VIPS_INTERPRETATION_sRGB, NULL) != 0) {
      fail_response(response, "InvalidImageError");
      VIPS_UNREF(image);
      return 1;
    }
  } else {
    srgb = image;
    g_object_ref(srgb);
  }
  gboolean has_alpha = vips_image_hasalpha(srgb);
  if (has_alpha) {
    if (vips_premultiply(srgb, &work, NULL) != 0) {
      fail_response(response, "InvalidImageError");
      VIPS_UNREF(image);
      VIPS_UNREF(srgb);
      return 1;
    }
  } else {
    work = srgb;
    g_object_ref(work);
  }
  if (vips_stats(work, &stats, NULL) != 0) {
    fail_response(response, "InvalidImageError");
    VIPS_UNREF(image);
    VIPS_UNREF(srgb);
    VIPS_UNREF(work);
    return 1;
  }
  size_t len = 0;
  double *matrix = (double *)vips_image_write_to_memory(stats, &len);
  if (!matrix) {
    fail_response(response, "InvalidImageError");
    VIPS_UNREF(image);
    VIPS_UNREF(srgb);
    VIPS_UNREF(work);
    VIPS_UNREF(stats);
    return 1;
  }
  int columns = vips_image_get_width(stats), bands = vips_image_get_bands(work);
  int colour_bands = has_alpha ? bands - 1 : bands;
  if (colour_bands > 3) {
    colour_bands = 3;
  }
  if (colour_bands < 1) {
    colour_bands = 1;
  }
  double alpha_mean = has_alpha ? matrix[(bands - 1 + 1) * columns + 4] : 255.0;
  int rgb[3];
  for (int b = 0; b < 3; b++) {
    int src = b < colour_bands ? b : colour_bands - 1;
    double value = matrix[(src + 1) * columns + 4];
    if (has_alpha) {
      value = alpha_mean > 0.0 ? value * 255.0 / alpha_mean : 0.0;
    }
    int iv = (int)llround(value);
    if (iv < 0) {
      iv = 0;
    }
    if (iv > 255) {
      iv = 255;
    }
    rgb[b] = iv;
  }
  g_free(matrix);
  char hex[7];
  snprintf(hex, sizeof(hex), "%02X%02X%02X", rgb[0], rgb[1], rgb[2]);
  write_value_string(response, hex);
  VIPS_UNREF(image);
  VIPS_UNREF(srgb);
  VIPS_UNREF(work);
  VIPS_UNREF(stats);
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: %s COMMAND --response PATH ...\n", argv[0]);
    return 2;
  }
  double started = now_ms();
  options_t opts;
  parse_options(argc, argv, &opts);
  const char *response = opt_required(&opts, "response");
  if (init_vips(argv[0]) != 0) {
    fail_response(response, "VipsUnavailableError");
    return 1;
  }
  const char *cmd = argv[1];
  int rc;
  if (strcmp(cmd, "probe") == 0) {
    rc = cmd_probe(&opts, started);
  } else if (strcmp(cmd, "orientation") == 0) {
    rc = cmd_orientation(&opts);
  } else if (strcmp(cmd, "pages") == 0) {
    rc = cmd_pages(&opts);
  } else if (strcmp(cmd, "thumbnail") == 0) {
    rc = cmd_thumbnail(&opts, started);
  } else if (strcmp(cmd, "resize") == 0) {
    rc = cmd_resize(&opts, started);
  } else if (strcmp(cmd, "crop-north") == 0) {
    rc = cmd_crop_north(&opts, started);
  } else if (strcmp(cmd, "convert") == 0) {
    rc = cmd_convert(&opts, started);
  } else if (strcmp(cmd, "dominant-color") == 0) {
    rc = cmd_dominant_color(&opts);
  } else {
    write_error(response, "ArgumentError", "unsupported helper command");
    rc = 2;
  }
  vips_shutdown();
  return rc;
}
