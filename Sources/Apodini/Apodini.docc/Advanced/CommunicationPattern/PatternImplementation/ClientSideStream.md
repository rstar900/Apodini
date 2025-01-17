# Client-Side Stream

Provide an implementation of a client-side stream.

<!--
                  
This source file is part of the Apodini open source project

SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>

SPDX-License-Identifier: MIT
             
-->

## Overview

In order to implement a client-side stream a `Handler` can rely on a constant connection that can be observed using the `@Environment` property wrapper:
You can access the connection state using the `Connection`'s `state` property that is retrieved by the `@Environment(\.connection)` property wrapper:

```swift
struct SingleParameterHandler: Handler {
    @Parameter var name: String
    @Environemnt(\.connection) var connection: Connection


    func handle() -> Response<String> {
        print(name)

        if connection.state == .end {
            return .final("End")
        } else { // connection.state == .open
            return .nothing // Send no reponse to the client as the connection is not yet terminated
        }
    }
}
```

To take full advantage of client-side streams, web services can collect content state from the client across multiple requests using `@State`. The following code allows for collecting an undefined number of `names` an then greeting all of them at once.

```swift
struct Greeter: Handler {
    @Parameter var name: String
    @State var names: [String] = []
    @Environemnt(\.connection) var connection: Connection


    func handle() -> Response<String> {
        names.append(name)
        if connection.state == .end {
            return .final("Hello \(names.joined(seperator: ", "))!")
        } else {
            return .nothing
        }
    }
}
```

## Collection

One should be implement something similar to the following concept by creating a custom `DynamicProperty`. However, the `@CollectableParameter` is not part of Apodini public interface yet.

The above pattern can be simplified into a single property wrapper called `@CollectableParameter` that manages the triplet of `@Parameter`, `@State` and `@Environment(\.connection)` for us.

```swift
struct SingleParameter: Handler {
    @CollectableParameter var names: [String]


    func handle() -> Response<String> {
        if $names.state == .end {
            // Joins all names in the array using commas.
            return .final("Hello \(names.joined(", "))!")
        } else {
            return .nothing
        }
    }
}
```

 Middlewares and Protocols that don't implement client-side streaming only accept a single request that can include the `@CollectableParameter` as a collection.


 In addition some types might conform to `Collectable` that requires a reduce function:

 ```swift
protocol Collectable {
    associatedtype Value
 

    static var defaultValue: Self.Value { get }


    static func reduce(value: inout Self.Value, nextValue: () -> Self.Value)
}
 ```

This enables `Handler`s to expose the `@CollectableParameter` as a single type:

```swift
struct NameCollector: Collectable {
    static var defaultValue: String = ""
 

    static func reduce(value: inout String, nextValue: String) {
        value.append(", \(nextValue)")
    }
}

struct Greeter: Handler {
    @CollectableParameter(NameCollector.self) var names: String


    func handle() -> Response<String> {
        if $names.state == .end {
            // Joins all names in the array using commas.
            return .final("Hello \(names)!")
        } else {
            return .nothing
        }
    }
}
 ```

