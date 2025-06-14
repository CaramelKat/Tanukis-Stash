//
//  TagModel.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 7/15/22.
//

import SwiftUI

struct TagContent: Decodable {
    let id: Int;
    let name: String;
    let post_count: Int;
    let category: Int;
    let antecedent_name: String?;
}
