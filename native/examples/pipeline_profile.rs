use std::env;
use std::path::PathBuf;

use native::codecs::jpeg::{DEFAULT_BACKGROUND, DEFAULT_QUALITY};
use native::crop::{AspectMismatchPolicy, CropRegion};
use native::filesystem::OutputTarget;
use native::pipeline::{
    FileCropRequest, FileProcessTimings, OutputCodec, process_image_file_profiled,
};
use native::pixel::PixelLimits;
use native::resize::ResizeFilter;

fn main() {
    let arguments = env::args().skip(1).collect::<Vec<_>>();
    if arguments.len() != 5 {
        eprintln!("usage: pipeline_profile <input> <output> <width> <height> <jpeg|png|webp>");
        std::process::exit(64);
    }
    let input = PathBuf::from(&arguments[0]);
    let output = PathBuf::from(&arguments[1]);
    let width = arguments[2].parse::<u32>().expect("valid output width");
    let height = arguments[3].parse::<u32>().expect("valid output height");
    let output_codec = match arguments[4].as_str() {
        "jpeg" => OutputCodec::Jpeg {
            quality: DEFAULT_QUALITY,
            background: DEFAULT_BACKGROUND,
        },
        "png" => OutputCodec::Png,
        "webp" => OutputCodec::WebP {
            lossless: false,
            quality: 80,
        },
        value => panic!("unsupported output codec {value}"),
    };
    let (_, timings) = process_image_file_profiled(
        &input,
        OutputTarget::explicit(&output, true).expect("output target"),
        FileCropRequest {
            region: CropRegion::Normalized {
                left: 0.0,
                top: 0.0,
                width: 1.0,
                height: 1.0,
            },
            output_size: Some((width, height)),
            aspect_mismatch_policy: AspectMismatchPolicy::Stretch,
            resize_filter: ResizeFilter::Bilinear,
            limits: PixelLimits::default(),
            output_codec,
        },
    )
    .expect("process image");
    print_timings(timings);
}

fn print_timings(timings: FileProcessTimings) {
    println!("inspect={:.2}ms", timings.inspect.as_secs_f64() * 1000.0);
    println!("open={:.2}ms", timings.open.as_secs_f64() * 1000.0);
    println!("decode={:.2}ms", timings.decode.as_secs_f64() * 1000.0);
    println!("pixels={:.2}ms", timings.pixels.as_secs_f64() * 1000.0);
    println!("staging={:.2}ms", timings.staging.as_secs_f64() * 1000.0);
    println!("encode={:.2}ms", timings.encode.as_secs_f64() * 1000.0);
    println!("commit={:.2}ms", timings.commit.as_secs_f64() * 1000.0);
    println!("total={:.2}ms", timings.total().as_secs_f64() * 1000.0);
}
