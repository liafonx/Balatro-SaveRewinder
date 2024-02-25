//
//  File.swift
//
//
//  Created by mi on 2022/11/26.
//

import Foundation

/*
 *  FSEventStreamCreateFlag
 *
 *  Discussion:
 *    Flags that can be passed to the FSEventStreamCreate...()
 *    functions to modify the behavior of the stream being created.
 */
public struct FSEventStreamCreateFlag: OptionSet {
	public var rawValue: Int

	public init(rawValue: Int) {
		self.rawValue = rawValue
	}

	init(_ rawValue: Int) {
		self.rawValue = rawValue
	}
	/*
	 * The framework will invoke your callback function with CF types
	 * rather than raw C types (i.e., a CFArrayRef of CFStringRefs,
	 * rather than a raw C array of raw C string pointers). See
	 * FSEventStreamCallback.
	 */
	public static let directoryEvents = FSEventStreamCreateFlag(0x00000000)

	/*
	 * The framework will invoke your callback function with CF types
	 * rather than raw C types (i.e., a CFArrayRef of CFStringRefs,
	 * rather than a raw C array of raw C string pointers). See
	 * FSEventStreamCallback.
	 */
	public static let useCFTypes = FSEventStreamCreateFlag(0x00000001)

	/*
	 * Affects the meaning of the latency parameter. If you specify this
	 * flag and more than latency seconds have elapsed since the last
	 * event, your app will receive the event immediately. The delivery
	 * of the event resets the latency timer and any further events will
	 * be delivered after latency seconds have elapsed. This flag is
	 * useful for apps that are interactive and want to react immediately
	 * to changes but avoid getting swamped by notifications when changes
	 * are occurringin rapid succession. If you do not specify this flag,
	 * then when an event occurs after a period of no events, the latency
	 * timer is started. Any events that occur during the next latency
	 * seconds will be delivered as one group (including that first
	 * event). The delivery of the group of events resets the latency
	 * timer and any further events will be delivered after latency
	 * seconds. This is the default behavior and is more appropriate for
	 * background, daemon or batch processing apps.
	 */
	public static let noDefer = FSEventStreamCreateFlag(0x00000002)

	/*
	 * Request notifications of changes along the path to the path(s)
	 * you're watching. For example, with this flag, if you watch
	 * "/foo/bar" and it is renamed to "/foo/bar.old", you would receive
	 * a RootChanged event. The same is true if the directory "/foo" were
	 * renamed. The event you receive is a special event: the path for
	 * the event is the original path you specified, the flag
	 * kFSEventStreamEventFlagRootChanged is set and event ID is zero.
	 * RootChanged events are useful to indicate that you should rescan a
	 * particular hierarchy because it changed completely (as opposed to
	 * the things inside of it changing). If you want to track the
	 * current location of a directory, it is best to open the directory
	 * before creating the stream so that you have a file descriptor for
	 * it and can issue an F_GETPATH fcntl() to find the current path.
	 */
	public static let watchRoot = FSEventStreamCreateFlag(0x00000004)

	/*
	 * Don't send events that were triggered by the current process. This
	 * is useful for reducing the volume of events that are sent. It is
	 * only useful if your process might modify the file system hierarchy
	 * beneath the path(s) being monitored. Note: this has no effect on
	 * historical events, i.e., those delivered before the HistoryDone
	 * sentinel event.  Also, this does not apply to RootChanged events
	 * because the WatchRoot feature uses a separate mechanism that is
	 * unable to provide information about the responsible process.
	 */
	public static let ignoreSelf = FSEventStreamCreateFlag(0x00000008)

	/*
	 * Request file-level notifications.  Your stream will receive events
	 * about individual files in the hierarchy you're watching instead of
	 * only receiving directory level notifications.  Use this flag with
	 * care as it will generate significantly more events than without it.
	 */
	public static let fileEvents = FSEventStreamCreateFlag(0x00000010)

	/*
	 * Tag events that were triggered by the current process with the "OwnEvent" flag.
	 * This is only useful if your process might modify the file system hierarchy
	 * beneath the path(s) being monitored and you wish to know which events were
	 * triggered by your process. Note: this has no effect on historical events, i.e.,
	 * those delivered before the HistoryDone sentinel event.
	 */
	public static let markSelf = FSEventStreamCreateFlag(0x00000020)

	/*
	 * Requires static let useCFTypes and instructs the
	 * framework to invoke your callback function with CF types but,
	 * instead of passing it a CFArrayRef of CFStringRefs, a CFArrayRef of
	 * CFDictionaryRefs is passed.  Each dictionary will contain the event
	 * path and possibly other "extended data" about the event.  See the
	 * kFSEventStreamEventExtendedData*Key definitions for the set of keys
	 * that may be set in the dictionary.  (See also FSEventStreamCallback.)
	 */
	public static let useExtendedData = FSEventStreamCreateFlag(0x00000040)

	/*
	 * When requesting historical events it is possible that some events
	 * may get skipped due to the way they are stored.  With this flag
	 * all historical events in a given chunk are returned even if their
	 * event-id is less than the sinceWhen id.  Put another way, deliver
	 * all the events in the first chunk of historical events that contains
	 * the sinceWhen id so that none are skipped even if their id is less
	 * than the sinceWhen id.  This overlap avoids any issue with missing
	 * events that happened at/near the time of an unclean restart of the
	 * client process.
	 */
	public static let fullHistory = FSEventStreamCreateFlag(0x00000080)
}

extension FSEventStreamCreateFlags {
	public init(_ flag: FSEventStreamCreateFlag) {
		self = FSEventStreamCreateFlags(flag.rawValue)
	}
}

/*
 *  FSEventStreamEventFlag
 *
 *  Discussion:
 *    Flags that can be passed to your FSEventStreamCallback function.
 *
 *    It is important to note that event flags are simply hints about the
 *    sort of operations that occurred at that path.
 *
 *    Furthermore, the FSEvent stream should NOT be treated as a form of
 *    historical log that could somehow be replayed to arrive at the
 *    current state of the file system.
 *
 *    The FSEvent stream simply indicates what paths changed; and clients
 *    need to reconcile what is really in the file system with their internal
 *    data model - and recognize that what is actually in the file system can
 *    change immediately after you check it.
 */
@frozen
public enum FSEventStreamEventFlag: UInt32, CaseIterable {
	/*
	 * There was some change in the directory at the specific path
	 * supplied in this event.
	 */
	case directory = 0x00000000

	/*
	 * Your application must rescan not just the directory given in the
	 * event, but all its children, recursively. This can happen if there
	 * was a problem whereby events were coalesced hierarchically. For
	 * example, an event in /Users/jsmith/Music and an event in
	 * /Users/jsmith/Pictures might be coalesced into an event with this
	 * flag set and path=/Users/jsmith. If this flag is set you may be
	 * able to get an idea of whether the bottleneck happened in the
	 * kernel (less likely) or in your client (more likely) by checking
	 * for the presence of the informational flags
	 * kFSEventStreamEventFlagUserDropped or
	 * kFSEventStreamEventFlagKernelDropped.
	 */
	case mustScanSubDirs = 0x00000001

	/*
	 * The kFSEventStreamEventFlagUserDropped or
	 * kFSEventStreamEventFlagKernelDropped flags may be set in addition
	 * to the kFSEventStreamEventFlagMustScanSubDirs flag to indicate
	 * that a problem occurred in buffering the events (the particular
	 * flag set indicates where the problem occurred) and that the client
	 * must do a full scan of any directories (and their subdirectories,
	 * recursively) being monitored by this stream. If you asked to
	 * monitor multiple paths with this stream then you will be notified
	 * about all of them. Your code need only check for the
	 * kFSEventStreamEventFlagMustScanSubDirs flag; these flags (if
	 * present) only provide information to help you diagnose the problem.
	 */
	case userDropped = 0x00000002
	case kernelDropped = 0x00000004

	/*
	 * If kFSEventStreamEventFlagEventIdsWrapped is set, it means the
	 * 64-bit event ID counter wrapped around. As a result,
	 * previously-issued event ID's are no longer valid arguments for the
	 * sinceWhen parameter of the FSEventStreamCreate...() functions.
	 */
	case eventIdsWrapped = 0x00000008

	/*
	 * Denotes a sentinel event sent to mark the end of the "historical"
	 * events sent as a result of specifying a sinceWhen value in the
	 * FSEventStreamCreate...() call that created this event stream. (It
	 * will not be sent if kFSEventStreamEventIdSinceNow was passed for
	 * sinceWhen.) After invoking the client's callback with all the
	 * "historical" events that occurred before now, the client's
	 * callback will be invoked with an event where the
	 * kFSEventStreamEventFlagHistoryDone flag is set. The client should
	 * ignore the path supplied in this callback.
	 */
	case historyDone = 0x00000010

	/*
	 * Denotes a special event sent when there is a change to one of the
	 * directories along the path to one of the directories you asked to
	 * watch. When this flag is set, the event ID is zero and the path
	 * corresponds to one of the paths you asked to watch (specifically,
	 * the one that changed). The path may no longer exist because it or
	 * one of its parents was deleted or renamed. Events with this flag
	 * set will only be sent if you passed the flag
	 * kFSEventStreamCreateFlagWatchRoot to FSEventStreamCreate...() when
	 * you created the stream.
	 */
	case rootChanged = 0x00000020

	/*
	 * Denotes a special event sent when a volume is mounted underneath
	 * one of the paths being monitored. The path in the event is the
	 * path to the newly-mounted volume. You will receive one of these
	 * notifications for every volume mount event inside the kernel
	 * (independent of DiskArbitration). Beware that a newly-mounted
	 * volume could contain an arbitrarily large directory hierarchy.
	 * Avoid pitfalls like triggering a recursive scan of a non-local
	 * filesystem, which you can detect by checking for the absence of
	 * the MNT_LOCAL flag in the f_flags returned by statfs(). Also be
	 * aware of the MNT_DONTBROWSE flag that is set for volumes which
	 * should not be displayed by user interface elements.
	 */
	case mount = 0x00000040

	/*
	 * Denotes a special event sent when a volume is unmounted underneath
	 * one of the paths being monitored. The path in the event is the
	 * path to the directory from which the volume was unmounted. You
	 * will receive one of these notifications for every volume unmount
	 * event inside the kernel. This is not a substitute for the
	 * notifications provided by the DiskArbitration framework; you only
	 * get notified after the unmount has occurred. Beware that
	 * unmounting a volume could uncover an arbitrarily large directory
	 * hierarchy, although Mac OS X never does that.
	 */
	case unmount = 0x00000080

	/*
	 * A file system object was created at the specific path supplied in this event.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemCreated = 0x00000100

	/*
	 * A file system object was removed at the specific path supplied in this event.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemRemoved = 0x00000200

	/*
	 * A file system object at the specific path supplied in this event had its metadata modified.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemInodeMetaMod = 0x00000400

	/*
	 * A file system object was renamed at the specific path supplied in this event.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemRenamed = 0x00000800

	/*
	 * A file system object at the specific path supplied in this event had its data modified.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemModified = 0x00001000

	/*
	 * A file system object at the specific path supplied in this event had its FinderInfo data modified.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemFinderInfoMod = 0x00002000

	/*
	 * A file system object at the specific path supplied in this event had its ownership changed.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemChangeOwner = 0x00004000

	/*
	 * A file system object at the specific path supplied in this event had its extended attributes modified.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemXattrMod = 0x00008000

	/*
	 * The file system object at the specific path supplied in this event is a regular file.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemIsFile = 0x00010000

	/*
	 * The file system object at the specific path supplied in this event is a directory.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemIsDir = 0x00020000

	/*
	 * The file system object at the specific path supplied in this event is a symbolic link.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemIsSymlink = 0x00040000

	/*
	 * Indicates the event was triggered by the current process.
	 * (This flag is only ever set if you specified the MarkSelf flag when creating the stream.)
	 */
	case ownEvent = 0x00080000

	/*
	 * Indicates the object at the specified path supplied in this event is a hard link.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemIsHardlink = 0x00100000

	/* Indicates the object at the specific path supplied in this event was the last hard link.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemIsLastHardlink = 0x00200000

	/*
	 * The file system object at the specific path supplied in this event is a clone or was cloned.
	 * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
	 */
	case itemCloned = 0x00400000
}

public func FSEventStreamEventFlagFrom(_ value: FSEventStreamEventFlags) -> Set<FSEventStreamEventFlag> {
	var set = Set<FSEventStreamEventFlag>()
	for flag in FSEventStreamEventFlag.allCases where value & flag.rawValue != 0 {
		set.insert(flag)
	}
	return set
}
