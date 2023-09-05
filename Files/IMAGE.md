## Convert
Convert image between multiple formats.

### Options
Image converter takes the following parameters:

| Parameter | Description | Values | Default |
| :---: | :---: | :---: | :---: |
| Image format | Output image format | `HEIF`, `HEIF10`, `HEIC`, `HEICS`, `PNG`, `GIF`, `JPEG`, `TIFF`, `BMP`, `JPEG2000`, `ICO` | Format extracted from destination path or from the source image |
| Image size | Output image size to fit in or cropping options | `original` - Original image size is used</br> `.fit(CGSize)` - Scale image to fit in</br>`.crop(Crop)` - Crop image based on options | `.original` |
| Image quality | Image quality in range from 0.0 to 1.0, __ignored__ by lossless formats | `[0.0, 1.0]` | `1.0` |
| Frame rate | Output animated image frame rate, __ignored__ by static image formats | `Int?` | `nil` - equals to original |
| Skip Animation | May be used for converting animated image sequence into static image | `Boolean` | `false` |
| Preserve Alpha channel | Preserve or drop alpha channel from image | `Boolean` | `true` |
| Embed thumbnail | Embed image thumbnail into output file | `Boolean` | `false` |
| Optimized color | Optimize image colors for sharing | `Boolean` | `false` |
| Background color | Used by image formats without alpha channel or when `preserveAlphaChannel` is `true` | `CGColor?` | `nil` |
| Edit | Image operations | `Set<ImageOperation>` | `empty` |
| Image Framework | Preferred framework to use for image processing | `.ciImage`, `.cgImage`, `.vImage` | `.ciImage` |

__Usage__
```Swift
ImageSettings(
    format: .png,
    size: .fit(.fhd),
    quality: 0.75,
    frameRate: 24,
    skipAnimation: false,
    preserveAlphaChannel: true,
    embedThumbnail: false,
    optimizeColorForSharing: false,
    backgroundColor: .white,
    edit: [
        // rotate, flip, mirror and other image operations goes here
    ],
    preferredFramework: .vImage
)
```

## Resize
Resize image while preserving aspect ratio. Provide `CGSize` resolution for image to fit it. Width and height may be rounded to nearest even number.

Predefined resolutions are `SD`, `HD`, `Full HD`, `Ultra HD` which are accessible via `CGSize` extension.

__Usage__
```Swift
ImageSettings(size: .fit(.fhd))
ImageSettings(size: .fit(CGSize(width: 720, height: 720)))
```

## Crop
Crop the image. There are three initializers which at the end produce `CGRect` for cropping.

__Usage__
```Swift
ImageSettings(size: .crop(options: .init(size: CGSize(width: 720, height: 720), aligment: .center)))
ImageSettings(size: .crop(options: .init(origin: CGPoint(x: 256, y: 256), size: CGSize(width: 1080, height: 1080))))

// Crop and scale to fit
ImageSettings(size: .crop(fit: .fhd, options: .init(size: CGSize(width: 512, height: 512), aligment: .center)))
```

## Rotate
Rotate an image. There are three fill options (for non-90 degree multiply angles) - crop, color or blur.

__Showcase__
| <img src='https://github.com/starkdmi/MediaToolSwift/assets/21260939/f3dffc9c-e83b-4729-9ed2-89e433e30705'/> | <img src='https://github.com/starkdmi/MediaToolSwift/assets/21260939/bff8d555-f58c-4f41-a2b1-f879a82a420f'/> |
| :-: | :-: |
| [starfield_animation.heif](Tests/media/starfield_animation.heif) rotated by 30 degree with blurred extend | [rally_burst.heic](Tests/media/rally_burst.heic) rotated by 10 degree with blurred extend |
| <img src='https://github.com/starkdmi/MediaToolSwift/assets/21260939/aae9096d-683b-4e9b-bbd5-38987d92a97f'/> | <img src='https://github.com/starkdmi/MediaToolSwift/assets/21260939/a405b8d5-b66b-4716-9fa4-ece7b38474f7'/> |
| [iphone_13.heic](Tests/media/iphone_13_hdr_gain_map.HEIC) rotated by 30 with blurred extend | [iphone_x.heic](Tests/media/iphone_x.HEIC) rotated by 45 and with blurred extend using vImage |
| <img src='https://github.com/starkdmi/MediaToolSwift/assets/21260939/39b80124-2c55-4cc0-a3cc-c052aeea4e1a'/> | <img src='https://github.com/starkdmi/MediaToolSwift/assets/21260939/c6f584c0-d489-4ef4-9f0f-ca1a344e4190'/> |
| [starkdev.png](Tests/media/starkdev.png) rotated by 45 with transparent color extend | [iphone_x.jpg](Tests/media/iphone_x.jpg) rotated by 30 and cropped to fill |

<!--<picture><source srcset="starfield_animation_30.webp" /><source srcset="starfield_animation_30.gif" /><img src="starfield_animation_30.webp" alt="starfield_animation.heif rotated by 30 degree with blurred extend" /></picture>-->

__Usage__
```Swift
ImageSettings(edit: [
    .rotate(.angle(.clockwise)) // rotate by 90 degree
    .rotate(.angle(.pi/4)) // rotate by 45 degree and crop the edges
    .rotate(.angle(.pi/4), fill: .blur(kernel: 55)) // rotate by 45 degree with blurred extend on edges
    .rotate(.angle(.pi/4), fill: .color(alpha: 255, red: 255, green: 255, blue: 255)) // rotate by 45 degree with white color fill on edges
])
```

## Mirror and Flip
Reflect image horizontally or vertically.

__Usage__
```Swift
ImageSettings(edit: [.mirror, .flip])
```

## Frame Rate adjustment
Set custom animated image frame rate. Will not increase source image frame rate.

__Usage__
```Swift
ImageSettings(frameRate: 24)
```

## Image Frameworks
Three image frameworks are capable to execute the same image operations. The choice of framework is based on `preferredFramework` parameter and supported by framework image formats. For example `CIImage` cannot load animated image from file, so will fallback to `CGImage`.
