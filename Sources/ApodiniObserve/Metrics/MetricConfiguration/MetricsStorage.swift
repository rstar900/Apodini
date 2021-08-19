//
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//

import Apodini

/// The storage key for Metrics-related information
public struct MetricsStorageKey: StorageKey {
    public typealias Value = MetricsStorageValue
}

/// The storage value for Metrics-related information.
public struct MetricsStorageValue {
    public let configuration: MetricsConfiguration

    internal init(configuration: MetricsConfiguration) {
        self.configuration = configuration
    }
}