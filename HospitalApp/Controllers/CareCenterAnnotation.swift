//
//  CareCenterAnnotation.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-30.
//

import MapKit

class CareCenterAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let careCenter: CareCenter
    
    init(careCenter: CareCenter) {
        self.careCenter = careCenter
        self.coordinate = CLLocationCoordinate2D(latitude: careCenter.latitude, longitude: careCenter.longitude)
        self.title = careCenter.name
        self.subtitle = careCenter.fullAddress
        super.init()
    }
}
