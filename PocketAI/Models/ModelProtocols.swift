import Foundation

// MARK: - ModelProtocols.swift
// Protocols for model loading and catalog services.

/// Protocol for objects that can load and unload a model.
public protocol ModelLoadable: Sendable {
    func load(from url: URL) async throws
    func unload() async throws
    func isLoaded() async -> Bool
}

/// Protocol for model catalog data sources.
public protocol ModelCatalogProvider: Sendable {
    func fetchEntries() async throws -> [ModelCatalogEntry]
    func entry(withId id: String) async -> ModelCatalogEntry?
    func entries(for engineKind: ModelEngineKind) async -> [ModelCatalogEntry]
    func refresh() async throws
}
