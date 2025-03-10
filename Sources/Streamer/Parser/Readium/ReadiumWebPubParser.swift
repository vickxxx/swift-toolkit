//
//  ReadiumWebPubParser.swift
//  r2-streamer-swift
//
//  Created by Mickaël Menu on 25.06.19.
//
//  Copyright 2019 Readium Foundation. All rights reserved.
//  Use of this source code is governed by a BSD-style license which is detailed
//  in the LICENSE file present in the project repository where this source code is maintained.
//

import Foundation
import R2Shared

public enum ReadiumWebPubParserError: Error {
    case parseFailure(url: URL, Error?)
    case missingFile(path: String)
}

/// Parser for a Readium Web Publication (packaged, or as a manifest).
public class ReadiumWebPubParser: PublicationParser, Loggable {
    
    public enum Error: Swift.Error {
        case manifestNotFound
        case invalidManifest
    }
    
//    private let pdfFactory: PDFDocumentFactory
    private let httpClient: HTTPClient
    public init(httpClient: HTTPClient){
        self.httpClient = httpClient
    }
    
//    public init(pdfFactory: PDFDocumentFactory, httpClient: HTTPClient) {
//        self.pdfFactory = pdfFactory
//        self.httpClient = httpClient
//    }
//
    public func parse(asset: PublicationAsset, fetcher: Fetcher, warnings: WarningLogger?) throws -> Publication.Builder? {
        guard let mediaType = asset.mediaType(), mediaType.isReadiumWebPubProfile else {
            return nil
        }
        
        let isPackage = !mediaType.isRWPM

        // Reads the manifest data from the fetcher.
        guard let manifestData: Data = (
            isPackage
                ? try? fetcher.readData(at: "/manifest.json")
                // For a single manifest file, reads the first (and only) file in the fetcher.
                : try? fetcher.readData(at: fetcher.links.first)
        ) else {
            throw Error.manifestNotFound
        }
        
        let manifest = try Manifest(json: JSONSerialization.jsonObject(with: manifestData), isPackaged: isPackage)
        var fetcher = fetcher
        
        // For a manifest, we discard the `fetcher` provided by the Streamer, because it was only
        // used to read the manifest file. We use an `HTTPFetcher` instead to serve the remote
        // resources.
        if !isPackage {
            let baseURL = manifest.link(withRel: .`self`)?.url(relativeTo: nil)?.deletingLastPathComponent()
            fetcher = HTTPFetcher(client: httpClient, baseURL: baseURL)
        }
        
        let userProperties = UserProperties()
        if mediaType.matches(.readiumWebPub) {
            fetcher = TransformingFetcher(fetcher: fetcher, transformers: [
                EPUBHTMLInjector(metadata: manifest.metadata, userProperties: userProperties).inject(resource:)
            ])
        }

        if mediaType.matches(.lcpProtectedPDF) {
            // Checks the requirements from the spec, see. https://readium.org/lcp-specs/drafts/lcpdf
            guard
                !manifest.readingOrder.isEmpty,
                manifest.readingOrder.all(matchMediaType: .pdf) else
            {
                throw Error.invalidManifest
            }
        }

        return Publication.Builder(
            mediaType: mediaType,
            format: (mediaType.matches(.lcpProtectedPDF) ? .pdf : .webpub),
            manifest: manifest,
            fetcher: fetcher,
            servicesBuilder: PublicationServicesBuilder(setup: {
                switch mediaType {
//                case .lcpProtectedPDF:
//                    $0.setPositionsServiceFactory(LCPDFPositionsService.makeFactory(pdfFactory: self.pdfFactory))
                case .divina, .divinaManifest:
                    $0.setPositionsServiceFactory(PerResourcePositionsService.makeFactory(fallbackMediaType: "image/*"))
                case .readiumAudiobook, .readiumAudiobookManifest, .lcpProtectedAudiobook:
                    $0.setLocatorServiceFactory(AudioLocatorService.makeFactory())
                case .readiumWebPub:
                    $0.setSearchServiceFactory(_StringSearchService.makeFactory())
                default:
                    break
                }
            }),
            setupPublication: { publication in
                if mediaType.matches(.readiumWebPub) {
                    publication.userProperties = userProperties
                    publication.userSettingsUIPreset = EPUBParser.userSettingsPreset(for: publication.metadata)
                }
            }
        )
    }

    @available(*, unavailable, message: "Use an instance of `Streamer` to open a `Publication`")
    public static func parse(at url: URL) throws -> (PubBox, PubParsingCallback) {
        fatalError("Not available")
    }

}

private extension MediaType {

    /// Returns whether this media type is of a Readium Web Publication profile.
    var isReadiumWebPubProfile: Bool {
        matchesAny(
            .readiumWebPub, .readiumWebPubManifest, .readiumAudiobook, .readiumAudiobookManifest,
            .lcpProtectedAudiobook, .divina, .divinaManifest, .lcpProtectedPDF
        )
    }

}

@available(*, unavailable, renamed: "ReadiumWebPubParserError")
public typealias WEBPUBParserError = ReadiumWebPubParserError

@available(*, unavailable, renamed: "ReadiumWebPubParser")
public typealias WEBPUBParser = ReadiumWebPubParser
