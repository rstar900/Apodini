//
// Created by Andi on 29.12.20.
//
import NIO
import Foundation

struct ValidatedRequest<I: InterfaceExporter, H: Handler>: Request {
    var description: String {
        var request = "Validated Request:\n"
        if let convertible = exporterRequest as? CustomStringConvertible {
            request += convertible.description
        }
        return request
    }
    var debugDescription: String {
        var request = "Validated Request:\n"
        if let convertible = exporterRequest as? CustomDebugStringConvertible {
            request += convertible.debugDescription
        }
        return request
    }

    var exporter: I
    var exporterRequest: I.ExporterRequest
    
    let validatedParameterValues: [UUID: Any]

    let storedEndpoint: Endpoint<H>
    var endpoint: AnyEndpoint {
        storedEndpoint
    }

    var eventLoop: EventLoop

    init(
        for exporter: I,
        with request: I.ExporterRequest,
        using validatedParameterValues: [UUID: Any],
        on endpoint: Endpoint<H>,
        running eventLoop: EventLoop
    ) {
        self.exporter = exporter
        self.exporterRequest = request
        self.validatedParameterValues = validatedParameterValues
        self.storedEndpoint = endpoint
        self.eventLoop = eventLoop
    }

    func retrieveParameter<Element: Codable>(_ parameter: Parameter<Element>) throws -> Element {
        guard let value = validatedParameterValues[parameter.id] as? Element else {
            fatalError("ValidatedRequest could not retrieve parameter '\(parameter.id)' after validation.")
        }
        return value
    }
}