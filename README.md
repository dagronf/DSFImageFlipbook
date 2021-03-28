# DSFImageFlipbook

A simple 'flipbook' of images.

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

* Load up a number of images from a gif or movie, or add images individually.
* Define the duration for each (individual) frame
* Start!

DSFImageFlipbook will then present each image in the flipbook to the owner of the flipbook (using a block callback or combine publisher).

## Examples

### Using a callback block

```swift
let flipbook = DSFImageFlipbook()

...

// Add frames manually
flipbook.addFrame(image: image1, duration: 0.5)
flipbook.addFrame(image: image2, duration: 0.5)
flipbook.addFrame(image: image3, duration: 0.5)
flipbook.addFrame(image: image4, duration: 2.0)

// And start the animation
flipbook.start() { [weak self] (frame, current, count) in
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

flipbook.start()
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
