import SwiftUI
import MapKit
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 44.8125, longitude: 20.4612),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    @Published var userLocation: CLLocationCoordinate2D?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        requestLocationPermission()
    }
    
    func requestLocationPermission() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        userLocation = location.coordinate
    }
    
    func setRegionForUserLocation(defaultSpan: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)) {
        if let userLocation = userLocation {
            region = MKCoordinateRegion(center: userLocation, span: defaultSpan)
        }
    }
}

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var locations: [Location] = UserDefaultsManager.loadLocations()
    @State private var showingLocationsList = false
    @State private var newLocationName: String = ""
    @State private var pendingLocationCoordinate: CLLocationCoordinate2D?
    @State private var showingNameLocationView = false

    var body: some View {
        ZStack {
            MapViewWrapper(mapRegion: $locationManager.region, locations: $locations, onLongPress: { coordinate in
                pendingLocationCoordinate = coordinate
                showingNameLocationView = true
            }, onRegionChange: { region in
                locationManager.region = region
            })
            .ignoresSafeArea()
            
            if showingNameLocationView {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all) // Optional: to dim the background
                VStack {
                    NameLocationView(
                        newLocationName: $newLocationName,
                        onSave: {
                            if let coordinate = pendingLocationCoordinate, !newLocationName.isEmpty {
                                let newLocation = Location(name: newLocationName, coordinate: coordinate)
                                locations.append(newLocation)
                                UserDefaultsManager.saveLocations(locations)
                                showingNameLocationView = false
                            }
                        },
                        onCancel: {
                            pendingLocationCoordinate = nil
                            showingNameLocationView = false
                        }
                    )
                    .padding()
                }
                .frame(maxWidth: 300) // Adjust the width as needed
                .background(Color.white)
                .cornerRadius(10)
                .shadow(radius: 10)
            }

            VStack {
                Spacer()
                Button(action: {
                    showingLocationsList = true
                }) {
                    Text("Show Saved Locations")
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.bottom, 10)
                .sheet(isPresented: $showingLocationsList) {
                    LocationsListView(locations: $locations, onSelectLocation: { location in
                        locationManager.region.center = location.coordinate
                        showingLocationsList = false
                    })
                }
                Button(action: {
                    locationManager.setRegionForUserLocation()
                }) {
                    Text("Show My Location")
                        .padding()
                        .frame(width: 200, height: 52) // Set width and height to make it square
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                .padding(.bottom, 40)
            }
        }
        .onChange(of: locations) { _ in
            UserDefaultsManager.saveLocations(locations)
        }
    }
}



struct NameLocationView: View {
    @Binding var newLocationName: String
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack {
            Text("Enter a name for this location:")
            TextField("Location name", text: $newLocationName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            HStack {
                Button("Save", action: onSave)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                Button("Cancel", action: onCancel)
                    .padding()
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

struct Location: Identifiable, Codable, Equatable {
    let id = UUID()
    var name: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: Location, rhs: Location) -> Bool {
        return lhs.id == rhs.id
    }
}

extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}

struct LocationsListView: View {
    @Binding var locations: [Location]
    var onSelectLocation: (Location) -> Void

    var body: some View {
        NavigationView {
            List {
                ForEach(locations) { location in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(location.name)
                            Text("Lat: \(location.coordinate.latitude), Lon: \(location.coordinate.longitude)")
                        }
                        Spacer()
                        Button(action: {
                            locations.removeAll { $0.id == location.id }
                            UserDefaultsManager.saveLocations(locations)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(BorderlessButtonStyle())  // Use BorderlessButtonStyle for delete button
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectLocation(location)
                    }
                }
            }
            .navigationTitle("Marked Locations")
        }
    }
}

struct MapViewWrapper: UIViewRepresentable {
    @Binding var mapRegion: MKCoordinateRegion
    @Binding var locations: [Location]
    var onLongPress: (CLLocationCoordinate2D) -> Void
    var onRegionChange: (MKCoordinateRegion) -> Void
    
    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapViewWrapper
        
        init(parent: MapViewWrapper) {
            self.parent = parent
        }
        
        @objc func handleLongPressGesture(gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let touchPoint = gesture.location(in: gesture.view)
            let mapView = gesture.view as! MKMapView
            let coordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
            
            parent.onLongPress(coordinate)
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mapView.region)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.setRegion(mapRegion, animated: false)
        mapView.delegate = context.coordinator
        
        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPressGesture(gesture:)))
        mapView.addGestureRecognizer(longPressGesture)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if uiView.region.center.latitude != mapRegion.center.latitude ||
            uiView.region.center.longitude != mapRegion.center.longitude ||
            uiView.region.span.latitudeDelta != mapRegion.span.latitudeDelta ||
            uiView.region.span.longitudeDelta != mapRegion.span.longitudeDelta {
            uiView.setRegion(mapRegion, animated: true)
        }
        
        uiView.removeAnnotations(uiView.annotations)
        let annotations = locations.map { location -> MKPointAnnotation in
            let annotation = MKPointAnnotation()
            annotation.coordinate = location.coordinate
            annotation.title = location.name
            return annotation
        }
        uiView.addAnnotations(annotations)
    }
}

class UserDefaultsManager {
    static let locationsKey = "savedLocations"
    
    static func saveLocations(_ locations: [Location]) {
        if let data = try? JSONEncoder().encode(locations) {
            UserDefaults.standard.set(data, forKey: locationsKey)
        }
    }
    
    static func loadLocations() -> [Location] {
        if let data = UserDefaults.standard.data(forKey: locationsKey),
           let locations = try? JSONDecoder().decode([Location].self, from: data) {
            return locations
        }
        return []
    }
}
