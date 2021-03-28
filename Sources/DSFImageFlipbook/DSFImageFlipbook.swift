//
//  DSFImageFlipbook.swift
//
//  Created by Darren Ford on 26/3/21.
//
//  MIT License
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import AVFoundation
import CoreGraphics
import Foundation

#if canImport(Combine)
import Combine
#endif

#if os(macOS)
import AppKit
#endif

public class DSFImageFlipbook {
	public typealias AnimationFrameChangedCallback = (Frame, _ current: Int, _ count: Int) -> Void
	public typealias AnimationDidCompleteCallback = (StopReason) -> Void

	/// The allowable range for the playback speed
	public let playbackSpeedRange = (1.0 / 16.0 ... 16)

	/// Loading errors
	public enum LoadStatus: Error {
		/// An error occurred during loading
		case error
		/// User cancelled loading
		case cancelled
	}

	/// The reason that an animation stopped
	public enum StopReason {
		/// The caller specified a repeat count and all repeats have finished
		case animationComplete
		/// The animation was stopped by the 'user' (owner)
		case userStopped
	}

	/// A frame for the animation
	public struct Frame {
		/// The frame image
		public let image: CGImage
		/// The duration that the image should stay visible (in seconds)
		public let duration: CFTimeInterval
		/// Initializer
		public init(image: CGImage, duration: CFTimeInterval) {
			self.image = image
			self.duration = duration
		}
	}

	/// Returns the number of frames in the animation
	public var frameCount: Int {
		// Always called on the main thread
		precondition(Thread.isMainThread)
		return self.frames.count
	}

	/// The duration for all the frames in the flipbook (in seconds)
	public var duration: CFTimeInterval {
		precondition(Thread.isMainThread)
		return self.frames.reduce(0) { result, frame in
			result + frame.duration
		}
	}

	/// The valid range for the current frames
	public var frameRange: Range<Int> {
		precondition(Thread.isMainThread)
		return (0 ..< self.frames.count)
	}

	/// Callback when the animation completes.
	///
	/// Guaranteed to be called on the main thread
	public var animationDidComplete: AnimationDidCompleteCallback?

	public init() {
		if #available(OSX 10.15, iOS 13, tvOS 13, *) {
			_publisher = PassthroughSubject<Frame, Never>()
		}
		else {
			self._publisher = nil
		}
	}

	deinit {
		self.cleanup()
	}

	// MARK: Private

	/// Callback when the flipbook moves to the next image in the flipbook
	///
	/// Note that this is not guaranteed to be called on the main thread.
	private var animationFrameChangedCallback: AnimationFrameChangedCallback?

	// MARK: - Privates

	private var currentPlaybackSpeed: Double = 1.0

	// The array of frames in the flipbook
	private var frames = [Frame]()

	// The frame currently being 'displayed'
	private var currentFrame: Int = 0

	// The timer instance for the current frame duration
	private var timer: Timer?

	// The number of times left to repeat the animation
	private var timesLeftToRepeat: UInt = .max

	// Our type-erased publisher so that we can handle pre-Combine versions of the OS
	private let _publisher: AnyObject?
}

// MARK: - Adding frames

public extension DSFImageFlipbook {
	/// Adds a new frame to the end of the animation
	func addFrame(_ frame: Frame) {
		// Always called on the main thread
		precondition(Thread.isMainThread)

		self.frames.append(frame)
	}

	/// Adds a new image frame and its duration to the end of the animation
	@inlinable func addFrame(image: CGImage, duration: CFTimeInterval) {
		self.addFrame(Frame(image: image, duration: duration))
	}

	/// Remove all the frames in the animation
	func removeAll() {
		// Always called on the main thread
		precondition(Thread.isMainThread)

		self.frames = []
		self.currentFrame = 0
	}

	/// Set the duration for all frames to the provided duration
	func setAllFrameDurations(to duration: CFTimeInterval) {
		// Always called on the main thread
		precondition(Thread.isMainThread)

		let updated = self.frames.map { Frame(image: $0.image, duration: duration) }
		self.frames = updated
	}
}

// MARK: - Loading

public extension DSFImageFlipbook {
	/// Load frames from image data (eg. the contents of a gif)
	/// - Parameter imageData: the data containing the image to load
	/// - Returns: the number of frames loaded from the image, or 0 on failure
	func loadFrames(from imageData: Data) -> Int {
		// Always called on the main thread
		precondition(Thread.isMainThread, "loadFrames() called on a background thread!")

		self.frames = []
		self.currentFrame = 0

		var loadedFrames: [Frame] = []
		guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
			return 0
		}

		let count = CGImageSourceGetCount(source)
		for frame in 0 ..< count {
			guard let image = CGImageSourceCreateImageAtIndex(source, frame, nil),
					let properties: [String: Any?] = CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [String: Any?],
					let gifProperties: [String: Any?] = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any?],
					let duration = gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber else
			{
				return 0
			}

			let f = Frame(image: image, duration: duration.doubleValue as CFTimeInterval)
			loadedFrames.append(f)
		}
		self.frames = loadedFrames
		return loadedFrames.count
	}

	/// Load frame from a compatible movie file
	/// - Parameters:
	///   - url: The URL of the movie to extract frames from
	///   - frameCount: The number of frames to extract (spread evenly across the entire video)
	///   - frameDuration: (optional) The duration to assign to each frame. If not specified, uses frameCount / duration of video
	///   - shouldStop: A callback block to supply if you want to be able to cancel the loading
	/// - Returns: The number of frames extracted
	func loadFrames(
		from url: URL,
		frameCount: UInt,
		frameDuration: CFTimeInterval? = nil,
		shouldStop: (() -> Bool)? = nil,
		completion: @escaping (Result<DSFImageFlipbook, Error>) -> Void)
	{
		// Always called on the main thread
		precondition(Thread.isMainThread, "loadFrames() called on a background thread!")

		self.frames = []
		self.currentFrame = 0

		DispatchQueue.global(qos: .default).async { [weak self] in

			guard let `self` = self else { return }

			var loadedFrames: [Frame] = []

			let asset = AVURLAsset(url: url)
			let generator = AVAssetImageGenerator(asset: asset)
			generator.requestedTimeToleranceAfter = .zero
			generator.requestedTimeToleranceBefore = .zero

			let duration = CMTimeGetSeconds(asset.duration)
			let frameDiff = duration / Double(frameCount)
			let actualFrameDuration = frameDuration ?? frameDiff

			var frame: Int = 0
			while frame < frameCount {
				// Check to see if we should stop
				if shouldStop?() ?? false {
					// Always call the completion handler on the main thread
					DispatchQueue.main.async {
						completion(.failure(LoadStatus.cancelled))
					}
					return
				}

				let cmt = CMTime(seconds: Double(frame) * frameDiff, preferredTimescale: 1)
				var actual = CMTime()
				if let cgi = try? generator.copyCGImage(at: cmt, actualTime: &actual) {
					loadedFrames.append(Frame(image: cgi, duration: actualFrameDuration))
					frame += 1
				}
				else {
					Swift.print("Dropped frame \(frame)...")
				}
			}

			self.frames = loadedFrames

			// Always call the completion handler on the main thrad
			DispatchQueue.main.async {
				completion(.success(self))
			}
		}
	}
}

#if os(macOS)
public extension DSFImageFlipbook {
	/// Load frames from an NSImage
	/// - Parameter image: the image containing the frames to load
	/// - Returns: the number of frames loaded from the image, or 0 on failure
	func loadFrames(from image: NSImage) -> Int {
		// Always called on the main thread
		precondition(Thread.isMainThread, "loadFrames() called on a background thread!")

		self.currentFrame = 0

		var loadedFrames: [Frame] = []

		// Find the first representation thats a bitmap
		guard let br = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
				let frameCount = br.value(forProperty: NSBitmapImageRep.PropertyKey.frameCount) as? Int,
				frameCount > 0 else
		{
			return 0
		}

		for frame in 0 ..< frameCount {
			br.setProperty(NSBitmapImageRep.PropertyKey.currentFrame, withValue: frame as Any)

			guard let cgFrame = br.cgImage,
					let duration = br.value(forProperty: NSBitmapImageRep.PropertyKey.currentFrameDuration) as? CFTimeInterval else
			{
				return 0
			}

			let f = Frame(image: cgFrame, duration: duration)
			loadedFrames.append(f)
		}

		self.frames = loadedFrames
		return loadedFrames.count
	}
}
#endif

// MARK: - Animation handling

public extension DSFImageFlipbook {
	/// Are we currently animating?
	func isAnimating() -> Bool {
		return self.timer != nil
	}

	/// Start the flipbook animation
	/// - Parameters:
	///   - startAtFrame: The frame offset to start at
	///   - speed: The playback speed (limited to DSFImageFlipbook.playbackSpeedRange)
	///   - repeatCount: How many times to loop the animation. If .max, loops indefinitely
	///   - callback: The callback block to receive frames. Guaranteed to be called on the main thread
	func start(startAtFrame: Int = -1,
				  speed: Double = 1,
				  repeatCount: UInt = .max,
				  callback: AnimationFrameChangedCallback? = nil)
	{
		// Should always be called on the main thread
		precondition(Thread.isMainThread, "start() called on a background thread!")

		self.animationFrameChangedCallback = callback

		let frameOffset: Int
		if startAtFrame >= 0 {
			frameOffset = startAtFrame
		}
		else if self.isAtLastFrame {
			frameOffset = 0
		}
		else {
			frameOffset = self.currentFrame
		}
		self.currentFrame = frameOffset < self.frameCount ? frameOffset : 0

		self.timesLeftToRepeat = repeatCount
		self.currentPlaybackSpeed = self.playbackSpeedRange.contains(speed) ? speed : 1
		self.presentCurrentFrame()
	}

	/// Stop the animation if it is running
	/// - Parameter reason: (optional) The reason for stopping
	func stop(reason: StopReason = .userStopped) {
		// Should always be called on the main thread
		precondition(Thread.isMainThread, "stop() called on a background thread!")
		self.cleanup()

		self.animationDidComplete?(reason)
	}

	/// Returns the current frame
	func peek() -> Frame {
		// Should always be called on the main thread
		precondition(Thread.isMainThread, "peek() called on a background thread!")

		return self.frames[self.currentFrame]
	}

	/// Returns the frame at the specified offset, or nil if the offset is invalid
	func frame(at offset: Int) -> Frame? {
		// Should always be called on the main thread
		precondition(Thread.isMainThread, "frame() called on a background thread!")

		guard self.frameRange.contains(offset) else {
			return nil
		}
		return self.frames[offset]
	}

	/// Set the current frame position. Must be called on the main thread
	///
	/// If the animation is currently running, the animation is stopped
	@discardableResult
	func setCurrentFrame(_ offset: Int) -> Int? {
		// Always called on the main thread
		precondition(Thread.isMainThread, "setCurrentFrame() called on a background thread!")

		// Stop the animation if it is running
		self.stop(reason: StopReason.userStopped)

		guard self.frameRange.contains(offset) else {
			return nil
		}

		// Set the current frame offset …
		self.currentFrame = offset

		// … and tell the owner that the frame has changed.
		_ = self.emitCurrentFrame()

		return offset
	}
}

// MARK: - Combine handling

@available(macOS 10.15, iOS 13, tvOS 13, *)
extension DSFImageFlipbook {
	// Internal publisher to allow us to send new values
	private var passthroughSubject: PassthroughSubject<Frame, Never> {
		return self._publisher as! PassthroughSubject<Frame, Never>
	}

	/// Combine publisher.
	///
	/// Note that the publisher will send events on non-main threads, so its important
	/// for your listeners to swap to the main thread if they are updating UI
	public var publisher: AnyPublisher<Frame, Never> {
		return self.passthroughSubject.eraseToAnyPublisher()
	}
}

// MARK: - Private functions

private extension DSFImageFlipbook {
	// Returns true if the current frame is the last frame
	private var isAtLastFrame: Bool {
		// Must always called on the main thread
		precondition(Thread.isMainThread, "isAtLastFrame() called on a background thread!")
		return self.currentFrame >= self.frameCount - 1
	}

	private func cleanup() {
		self.timer?.invalidate()
		self.timer = nil
	}

	// This will emit a frame on the main thread
	private func emitCurrentFrame() -> Frame {
		// Must always called on the main thread
		precondition(Thread.isMainThread, "emitCurrentFrame called on a background thread!")

		let cFrame = self.frames[self.currentFrame]

		// Emit via combine if its available
		if #available(macOS 10.15, iOS 13, tvOS 13, *) {
			self.passthroughSubject.send(cFrame)
		}

		// Emit on the callback if its available
		self.animationFrameChangedCallback?(cFrame, self.currentFrame, self.frames.count)

		return cFrame
	}

	private func presentCurrentFrame() {
		// Must always called on the main thread
		precondition(Thread.isMainThread, "presentCurrentFrame called on a background thread!")

		// Emit the frame
		let emitFrame = self.emitCurrentFrame()

		// Calculate the duration that this frame has to be "on-screen"
		let frameDuration = emitFrame.duration / self.currentPlaybackSpeed

		if self.isAtLastFrame, self.timesLeftToRepeat != .max {
			self.timesLeftToRepeat -= 1
			if self.timesLeftToRepeat == 0 {
				self.stop(reason: .animationComplete)
				return
			}
		}

		// And wait until we have to present the next frame
		self.startTimerForNextInterval(frameDuration)
	}

	private func startTimerForNextInterval(_ frameDuration: CFTimeInterval) {
		// Must always called on the main thread
		// Given this is only called from 'presentCurrentFrame' this doesn't need a precondition)
		precondition(Thread.isMainThread, "startTimerForNextInterval() called on a background thread!")

		// Run the timer on a background thread so that we don't block during UI activities like resizing the window
		DispatchQueue.global(qos: .userInteractive).async { [weak self] in
			self?.timer = Timer.scheduledTimer(withTimeInterval: frameDuration, repeats: false) { [weak self] _ in
				DispatchQueue.main.async { [weak self] in
					self?.moveToNextFrame()
				}
			}
			RunLoop.current.run()
		}
	}

	private func moveToNextFrame() {
		// Must always called on the main thread
		precondition(Thread.isMainThread, "moveToNextFrame() called on a background thread!")

		self.currentFrame = (self.currentFrame + 1) % self.frames.count
		self.presentCurrentFrame()
	}
}
