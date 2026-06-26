//
//  AppleMusicAffiliateManager.swift
//  TruWord Music
//
//  Created by Dillon Davis on 6/26/26.
//

import Foundation
import MusicKit

enum AppleMusicAffiliateType {
    case track
    case album
    case artist
}

struct AppleMusicAffiliateManager {
    
    private static let partnerID = "1010l3QqF"
    
    static func makeURL(
        type: AppleMusicAffiliateType,
        id: MusicItemID
    ) -> URL? {
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "music.apple.com"
        
        let path: String
        let ct: String
        
        switch type {
        case .track:
            path = "/us/song/\(id.rawValue)"
            ct = "truwordmusic_track_detail"
            
        case .album:
            path = "/us/album/\(id.rawValue)"
            ct = "truwordmusic_album_detail"
            
        case .artist:
            path = "/us/artist/\(id.rawValue)"
            ct = "truwordmusic_artist_detail"
        }
        
        components.path = path
        
        components.queryItems = [
            URLQueryItem(name: "itscg", value: "30200"),
            URLQueryItem(name: "itsct", value: "toolbox_linkbuilder"),
            URLQueryItem(name: "at", value: partnerID),
            URLQueryItem(name: "ct", value: ct),
            URLQueryItem(name: "mttnsubad", value: id.rawValue),
            URLQueryItem(name: "ls", value: "1"),
            URLQueryItem(name: "app", value: "music")
        ]
        
        return components.url
    }
}

