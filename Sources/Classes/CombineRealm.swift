//
//  Realm extensions for Combine
//
//  Check the LICENSE file for details
//  Created by David Collado
//  Based on original RxSwift Realm by Marin Todorov
//

import Foundation
import RealmSwift
import Combine

public enum RxRealmError: Error {
    case objectDeleted
    case unknown
}

// MARK: Realm Collections type extensions

/**
 `NotificationEmitter` is a protocol to allow for Realm's collections to be handled in a generic way.

 All collections already include a `addNotificationBlock(_:)` method - making them conform to `NotificationEmitter` just makes it easier to add Rx methods to them.

 The methods of essence in this protocol are `asPublisher(...)`, which allow for observing for changes on Realm's collections.
 */
public protocol NotificationEmitter {
    associatedtype ElementType: RealmCollectionValue

    /**
     Returns a `NotificationToken`, which while retained enables change notifications for the current collection.

     - returns: `NotificationToken` - retain this value to keep notifications being emitted for the current collection.
     */
    func observe(_ block: @escaping (RealmCollectionChange<Self>) -> Void) -> NotificationToken

    func toArray() -> [ElementType]

    func toAnyCollection() -> AnyRealmCollection<ElementType>
}

extension List: NotificationEmitter {
    public func toAnyCollection() -> AnyRealmCollection<Element> {
        return AnyRealmCollection<Element>(self)
    }

    public typealias ElementType = Element
    public func toArray() -> [Element] {
        return Array(self)
    }
}

extension AnyRealmCollection: NotificationEmitter {
    public func toAnyCollection() -> AnyRealmCollection<Element> {
        return AnyRealmCollection<ElementType>(self)
    }

    public typealias ElementType = Element
    public func toArray() -> [Element] {
        return Array(self)
    }
}

extension Results: NotificationEmitter {
    public func toAnyCollection() -> AnyRealmCollection<Element> {
        return AnyRealmCollection<ElementType>(self)
    }

    public typealias ElementType = Element
    public func toArray() -> [Element] {
        return Array(self)
    }
}

extension LinkingObjects: NotificationEmitter {
    public func toAnyCollection() -> AnyRealmCollection<Element> {
        return AnyRealmCollection<ElementType>(self)
    }

    public typealias ElementType = Element
    public func toArray() -> [Element] {
        return Array(self)
    }
}

/**
 `RealmChangeset` is a struct that contains the data about a single realm change set.

 It includes the insertions, modifications, and deletions indexes in the data set that the current notification is about.
 */
public struct RealmChangeset {
    /// the indexes in the collection that were deleted
    public let deleted: [Int]

    /// the indexes in the collection that were inserted
    public let inserted: [Int]

    /// the indexes in the collection that were modified
    public let updated: [Int]
}

final class RealmSubscription<Input, Failure: Swift.Error>: Subscription {
    private var subscriber: AnySubscriber<Input, Failure>?
    private let token: NotificationToken

    init(subscriber: AnySubscriber<Input, Failure>, handler: (AnySubscriber<Input, Failure>) -> NotificationToken) {
        self.subscriber = subscriber
        token = handler(subscriber)
    }

    public func request(_ demand: Subscribers.Demand) {
        // We do nothing here as we only want to send events when they occur.
        // See, for more info: https://developer.apple.com/documentation/combine/subscribers/demand
    }

    public func cancel() {
        token.invalidate()
        subscriber = nil
    }
}

struct RealmPublisher<Output, Failure: Swift.Error>: Publisher {

    public typealias Output = Output
    public typealias Failure = Failure

    private let handler: (AnySubscriber<Output, Failure>) -> NotificationToken

    init(handler: @escaping (AnySubscriber<Output, Failure>) -> NotificationToken) {
        self.handler = handler
    }
    public func receive<S>(subscriber: S) where S : Subscriber, S.Failure == Failure, S.Input == Output {
        subscriber.receive(subscription: RealmSubscription<Output, Failure>(subscriber: AnySubscriber(subscriber), handler: handler))
    }
}

public struct RealmError: Swift.Error {
    let underlyingError: Swift.Error
}

public extension AnyPublisher where Output: NotificationEmitter {
    /**
     Returns an `AnyPublisher<Output, Failure>` that emits each time the collection data changes.
     The observable emits an initial value upon subscription.

     - parameter from: A Realm collection of type `Element`: either `Results`, `List`, `LinkingObjects` or `AnyRealmCollection`.
     - parameter synchronousStart: whether the resulting `Publisher` should emit its first element synchronously (e.g. better for UI bindings)

     - returns: `AnyPublisher<Output, Failure>`, e.g. when called on `Results<Model>` it will return `AnyPublisher<Results<Model>>`, on a `List<User>` it will return `AnyPublisher<List<User>>`, etc.
     */
    static func collection(from collection: Output, synchronousStart: Bool)
        -> AnyPublisher<Output, RealmError> {
            return RealmPublisher<Output, RealmError>.init { subscriber  in
                return collection.observe { changeset in
                    let value: Output
                    switch changeset {
                    case let .initial(latestValue):
                        guard !synchronousStart else { return }
                        value = latestValue

                    case .update(let latestValue, _, _, _):
                        value = latestValue

                    case let .error(error):
                        subscriber.receive(completion: Subscribers.Completion.failure(RealmError(underlyingError: error)))
                        return
                    }
                    _ = subscriber.receive(value)
                }
            }.eraseToAnyPublisher()
    }

    /**
     Returns an `AnyPublisher<Array<Element.Element>>` that emits each time the collection data changes. The observable emits an initial value upon subscription.
     The result emits an array containing all objects from the source collection.

     - parameter from: A Realm collection of type `Element`: either `Results`, `List`, `LinkingObjects` or `AnyRealmCollection`.
     - parameter synchronousStart: whether the resulting Publisher should emit its first element synchronously (e.g. better for UI bindings)

     - returns: `AnyPublisher<Array<Element.Element>>`, e.g. when called on `Results<Model>` it will return `AnyPublisher<Array<Model>>`, on a `List<User>` it will return `AnyPublisher<Array<User>>`, etc.
     */
    static func array(from collection: Output, synchronousStart: Bool = true)
        -> AnyPublisher<Array<Output.ElementType>, RealmError> {
            return AnyPublisher.collection(from: collection, synchronousStart: synchronousStart)
                .map { $0.toArray() }
                .eraseToAnyPublisher()
    }


    /**
     Returns an `AnyPublisher<(Element, RealmChangeset?)>` that emits each time the collection data changes. The observable emits an initial value upon subscription.

     When the observable emits for the first time (if the initial notification is not coalesced with an update) the second tuple value will be `nil`.

     Each following emit will include a `RealmChangeset` with the indexes inserted, deleted or modified.

     - parameter from: A Realm collection of type `Element`: either `Results`, `List`, `LinkingObjects` or `AnyRealmCollection`.
     - parameter synchronousStart: whether the resulting Publisher should emit its first element synchronously (e.g. better for UI bindings)

     - returns: `AnyPublisher<(RealmChangesetPublisher<Element.Element>, RealmChangeset?)>`
     */
    static func changeset(from collection: Output, synchronousStart: Bool = true)
        -> AnyPublisher<(AnyRealmCollection<Output.ElementType>, RealmChangeset?), RealmError> {
            return RealmPublisher<(AnyRealmCollection<Output.ElementType>, RealmChangeset?), RealmError>.init { subscriber  in
                return collection.toAnyCollection().observe { changeset in
                    switch changeset {
                    case let .initial(value):
                        guard !synchronousStart else { return }
                        _ = subscriber.receive((value, nil))
                    case let .update(value, deletes, inserts, updates):
                        _ = subscriber.receive((value, RealmChangeset(deleted: deletes, inserted: inserts, updated: updates)))
                    case let .error(error):
                        subscriber.receive(completion: Subscribers.Completion.failure(RealmError(underlyingError: error)))
                        return
                    }
                }
            }.eraseToAnyPublisher()
    }

    /**
     Returns an `AnyPublisher<(Array<Element.Element>, RealmChangeset?)>` that emits each time the collection data changes. The observable emits an initial value upon subscription.

     This method emits an `Array` containing all the realm collection objects, this means they all live in the memory. If you're using this method to observe large collections you might hit memory warnings.

     When the observable emits for the first time (if the initial notification is not coalesced with an update) the second tuple value will be `nil`.

     Each following emit will include a `RealmChangeset` with the indexes inserted, deleted or modified.

     - parameter from: A Realm collection of type `Element`: either `Results`, `List`, `LinkingObjects` or `AnyRealmCollection`.
     - parameter synchronousStart: whether the resulting Publisher should emit its first element synchronously (e.g. better for UI bindings)

     - returns: `AnyPublisher<(Array<Element.Element>, RealmChangeset?)>`
     */
    static func arrayWithChangeset(from collection: Output, synchronousStart: Bool = true)
        -> AnyPublisher<([Output.ElementType], RealmChangeset?), RealmError> {
            return Self.changeset(from: collection)
                .map { ($0.toArray(), $1) }
                .eraseToAnyPublisher()
    }
}

public extension AnyPublisher {

    /**
     Returns an `AnyPublisher<(Realm, Realm.Notification)>` that emits each time the Realm emits a notification.

     The Publisher you will get emits a tuple made out of:

     * the realm that emitted the event
     * the notification type: this can be either `.didChange` which occurs after a refresh or a write transaction ends,
     or `.refreshRequired` which happens when a write transaction occurs from a different thread on the same realm file

     For more information look up: [Realm.Notification](https://realm.io/docs/swift/latest/api/Enums/Notification.html)

     - parameter realm: A Realm instance
     - returns: `AnyPublisher<(Realm, Realm.Notification)>`, which you can subscribe to
     */
    static func from(realm: Realm) -> AnyPublisher<(Realm, Realm.Notification), Failure> {
        return RealmPublisher<(Realm, Realm.Notification), Failure>.init { subscriber in
            return realm.observe { (notification: Realm.Notification, realm: Realm) in
                _ = subscriber.receive((realm, notification))
                _ = subscriber.receive(completion: Subscribers.Completion.finished)
            }
        }.eraseToAnyPublisher()
    }
}
