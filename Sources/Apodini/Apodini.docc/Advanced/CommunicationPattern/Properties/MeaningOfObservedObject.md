# ObservedObject

Description of ObservedObject property wrapper and its usage in Apodini.

<!--
                  
This source file is part of the Apodini open source project

SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>

SPDX-License-Identifier: MIT
             
-->

## Overview

The `@ObservedObject` wraps an `ObservableObject`. An `ObservableObject` may have multiple `@Published` properties. A `Handler` that contains an `@ObservedObject` registers callbacks to these `Published` properties and evaluates the `Handler` on each update.

## Lifetime

The lifetime of the `ObservedObject` itself depends on the way it is created. The developer could pass it in from the outside (e.g. from a lower `Component`) as sort of a singleton which lives until the process dies. If the `ObservedObject` is created inside the `Handler` it is recreated every time a new connection is established but lives for the complete lifetime of the `Handler`.

`ObservedObject`s can be globally declared by defining them in the `configuration` computed property of the web service using `EnvironmentObject(value, keyPath)`. This `Configuration` takes as arguments a key path that is used to retrieve the `ObservableObject` from a property wrapper `@ObservedObject(\.keyPath)` and the corresponding value that should be injected. The key path has to conform to `EnvironmentAccessible` and can be defined in a separate struct in the web service. Locally defined `ObservableObject`s don't require the use of a key path.

Example configuration of a global `ObservableObject`:

```swift
struct Bird: ObservableObject {
    var name: String
    var age: Int
}

struct BirdHandler: Handler {
    @Environment(\KeyStore.bird) var bird: Bird

    // ...
}

struct KeyStore: EnvironmentAccessible {
    var bird: Bird
}

var configuration: Configuration {
    EnvironmentObject(Bird(), \KeyStore.bird)
}
```

### Differentiate ObservableObjects

The property wrapper `@ObservedObject` provides a Boolean property  `changed` that can be accessed  an `ObservableObject` prefixed with `_`: `_observableObject.changed`. This value will evaluate to `true` if the corresponding `ObservableObject` caused the execution of the `Handler`. In every other case, `changed` will evaluate to `false`.

### Influence

The presence of `@ObservedObject` properties on a `Handler` signalizes exporting the endpoint as a Service-Side Stream makes sense. If the exporter decides to do so the lifetime of the `Handler` has to be extended accordingly. The `Handler` should stay alive until either `.end` or `.final(E)` was returned.

### Implementation-Details

#### Request-Response

Exporters that only support the Request-Response pattern cannot handle multiple service-messages. The default behavior would be to return the first non-`.nothing` `Response` as the response and destruct the `Handler` afterwards.

![document type: vision](https://apodini.github.io/resources/markdown-labels/document_type_vision.svg)

An advanced feature would be to allow for the developer to customize the strategy used for a certain endpoint, e.g. using `.downgrade(using strategy: Strategy)` on the according `Component`. `Strategy` could be the default `.cutOff` or `.collect`. The latter would result in the exported response-type to be `[Response]` and the `Handler` collecting all `.send(Response)` until the `Handler` is destructed when `.end` or `.final(E)` is returned.

#### Client-Side Stream

Refer to Request-Response.

#### Service-Side Stream

The Service-Side Stream can fully support the features provided by `@ObservedObject`. The `Handler` stays alive until either `.end` or `.final(E)` is returned.

#### Bidirectional Stream

Refer to Service-Side Stream.

## Control Flow

### Influence

`@ObservableObject`s emit events if one of their `wrappedProperty`'s `@Published` emits an event. The `Handler` is evaluated each time one of the observed `@Published`s' value changes.

### Implementation Details

Each exporter that supports `@ObservedObject`s must subscribe to them, no matter what communicational patterns it supports. Even for a request-response pattern the initial request providing `@Parameter`s could result in an `Action.nothing` being returned. In that case the required non-`.nothing` `Action` will result from an event that comes from one of the `@ObservedObject`s.

