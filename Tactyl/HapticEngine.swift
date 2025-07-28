//
//  HapticEngine.swift
//  Tactyl
//
//  Created by Ashish Patil on 29/07/25.
//

import Foundation
import CoreHaptics

class HapticEngine{
    
    var engine:CHHapticEngine!
    
    init()
    {
        do {
        self.engine =  try? CHHapticEngine()
    }
        catch{
            print(error)
        }
    }
    
    func defineHapticEvent()
    {
        
    }
}
