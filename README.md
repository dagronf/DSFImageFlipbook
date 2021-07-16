# DSFImageFlipbook

A simple 'flipbook' of images that can be presented as flipbook-style animation.

<p align="center">
    <img src="https://img.shields.io/github/v/tag/dagronf/DSFImageFlipbook" />
    <img src="https://img.shields.io/badge/Swift-5.0-orange.svg" />
    <img src="https://img.shields.io/badge/License-MIT-lightgrey" />
    <img src="https://img.shields.io/badge/spm-compatible-brightgreen.svg?style=flat" alt="Swift Package Manager" />
<br/>
    <img src="https://img.shields.io/badge/macOS-10.12+-blue" />
    <img src="https://img.shields.io/badge/iOS-13+-orange" />
    <img src="https://img.shields.io/badge/tvOS-13+-green" />
</p>

DSFImageFlipbook presents each image in the flipbook to the owner of the flipbook (using a block callback or combine publisher) for the duration of the image frame.

Supports :-

* loading images from a gif, a movie or manually frame-by-frame.
* repeat count
* speed
* scrubbing
* cancellation

## Why?

I wanted to put an animated gif in a dock tile. Due to the nature of `NSDockTile` you cannot just play an `NSImageView` as the `contentView` of the tile - the only time a dock tile updates is when you tell it to (via `display()`)

So I needed a class that could present me individual images at a defined time so that I could manually update the dock image.

## Examples

### Using a callback block

```swift
let flipbook = DSFImageFlipbook()

...

// Add frames manually
flipbook.addFrame(image: image1, duration: 0.5)   // first frame for 0.5 seconds
flipbook.addFrame(image: image2, duration: 0.5)   // second frame for 0.5 seconds
flipbook.addFrame(image: image3, duration: 0.5)   // third frame for 0.5 seconds
flipbook.addFrame(image: image4, duration: 2.0)   // last frame for 2.0 seconds

// And start the animation
flipbook.start() { [weak self] (frame, current, count, stop) in
   // Do something with the provided frame
}
```

### Using Combine (macOS 10.15+, iOS 13+, tvOS 13+)

```swift
let flipbook = DSFImageFlipbook()

// Load the frames from a gif
let gif = Bundle.main.image(forResource: NSImage.Name("animation.gif"))!
_ = flipbook.loadFrames(from: gif)

...

// Use a combine sink to listen to frame changes in localFlipbook
cancellable = flipbook.publisher
   .map { return $0.image }
   .sink(receiveValue: { [weak self] image in
       ... do something with 'image'
	})

// Start the animation at 2x the speed defined in the flipbook. Repeat 10 times.
flipbook.start(speed: 2, repeatCount: 10)
```

## License

MIT. Use it and abuse it for anything you want, just attribute my work. Let me know if you do use it somewhere, I'd love to hear about it!

```
MIT License

Copyright (c) 2021 Darren Ford

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
