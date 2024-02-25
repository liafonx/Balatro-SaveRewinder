//
//  FileMonitor.swift
//  
//
//  Created by mi on 2024/2/24.
//

import Foundation

// https://developer.apple.com/forums/thread/115387?answerId=355880022#355880022
class FileMonitor {
    let filePath: String
    let queue: DispatchQueue
    typealias Handler = (_ file: String, _ flags: Set<FSEventStreamEventFlag>) -> Void
    let handler: Handler

    init(filePath: String, queue: DispatchQueue = DispatchQueue(label: "FileMonitor.global.queue"), handler: @escaping Handler) {
        self.filePath = filePath
        self.queue = queue
        self.handler = handler
    }

    deinit {
        self.stop()
    }

    private var stream: FSEventStreamRef?

    @discardableResult
    func start() -> Bool {
        guard self.stream == nil else {
            return false
        }

        // Set up our context.
        //
        // `FSEventStreamCallback` is a C function, so we pass `self` to the
        // `info` pointer so that it get call our `handleUnsafeEvents(…)`
        // method.  This involves the standard `Unmanaged` dance:
        //
        // * Here we set `info` to an unretained pointer to `self`.
        // * Inside the function we extract that pointer as `obj` and then use
        //   that to call `handleUnsafeEvents(…)`.

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        // Create the stream.
        //
        // In this example I wanted to show how to deal with raw string paths,
        // so I’m not taking advantage of `kFSEventStreamCreateFlagUseCFTypes`
        // or the even cooler `kFSEventStreamCreateFlagUseExtendedData`.
        // swiftlint:disable unneeded_parentheses_in_closure_argument
        guard let stream = FSEventStreamCreate(
            nil,
            { (_, info, numEvents, eventPaths, eventFlags, eventIds) in
                let obj = Unmanaged<FileMonitor>.fromOpaque(info!).takeUnretainedValue()
                obj.handleUnsafeEvents(numEvents: numEvents, eventPaths: eventPaths, eventFlags: eventFlags, eventIDs: eventIds)
            },
            &context,
            [self.filePath] as NSArray,
            UInt64(kFSEventStreamEventIdSinceNow),
            1,
            FSEventStreamCreateFlags([.fileEvents, .useCFTypes, .ignoreSelf])
        ) else {
            return false
        }
        self.stream = stream

        // Now that we have a stream, schedule it on our target queue.

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            self.stream = nil
            return false
        }
        return true
    }

    private func handleUnsafeEvents(numEvents: Int, eventPaths: UnsafeMutableRawPointer, eventFlags: UnsafePointer<FSEventStreamEventFlags>, eventIDs: UnsafePointer<FSEventStreamEventId>) {
        guard
            let eventPathArray = unsafeBitCast(eventPaths, to: NSArray.self) as? [String]
        else {
            return
        }
        let eventFlagsArray = UnsafeBufferPointer(start: eventFlags, count: numEvents)
        let result = Dictionary(zip(eventPathArray, eventFlagsArray), uniquingKeysWith: {
            $1
        })
        for (path, flags) in result {
            self.handler(path, FSEventStreamEventFlagFrom(flags))
        }
    }

    func stop() {
        guard let stream = self.stream else {
            return          // We accept redundant calls to `stop`.
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        self.stream = nil
    }
}
