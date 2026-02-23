import SwiftUI
import MapKit
import Combine
import CoreLocation
import AVFoundation

// MARK: - 1. Transport Types Enum
enum TransportMode: String, CaseIterable {
    case drive = "car.fill"
    case transit = "bus.fill"
    case walk = "figure.walk"
    
    var type: MKDirectionsTransportType {
        switch self {
        case .drive: return .automobile
        case .transit: return .transit
        case .walk: return .walking
        }
    }
    
    func label(isChinese: Bool) -> String {
        switch self {
        case .drive: return isChinese ? "自駕" : "Drive"
        case .transit: return isChinese ? "公共交通" : "Transit"
        case .walk: return isChinese ? "步行" : "Walking"
        }
    }
}

// MARK: - 2. Map Style Mode
enum MapDisplayMode: String, CaseIterable {
    case standard
    case hybrid
    case imagery
    
    func label(isChinese: Bool) -> String {
        switch self {
        case .standard: return isChinese ? "標準" : "Standard"
        case .hybrid: return isChinese ? "混合" : "Hybrid"
        case .imagery: return isChinese ? "衛星" : "Satellite"
        }
    }
    
    var icon: String {
        switch self {
        case .standard: return "map"
        case .hybrid: return "square.3.layers.3d"
        case .imagery: return "globe.americas.fill"
        }
    }
}

// MARK: - 3. Data Model
struct School: Identifiable, Hashable {
    let id = UUID()
    let nameEN: String
    let nameCH: String
    let coordinate: CLLocationCoordinate2D
    let districtEN: String
    let addressEN: String
    let addressCH: String
    let levelEN: String
    let levelCH: String
    let financeTypeEN: String
    
    func name(isChinese: Bool) -> String {
        let n = isChinese ? nameCH : nameEN
        return n.isEmpty ? nameEN : n
    }
    
    func address(isChinese: Bool) -> String {
        let a = isChinese ? addressCH : addressEN
        return a.isEmpty ? addressEN : a
    }
    
    static func == (lhs: School, rhs: School) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    
    var searchableText: String {
        [
            nameEN,
            nameCH,
            addressEN,
            addressCH,
            districtEN,
            levelEN,
            levelCH,
            financeTypeEN
        ]
        .joined(separator: " ")
    }
    
    var mapIcon: String {
        let l = levelEN.lowercased()
        if l.contains("kindergarten") { return "teddybear.fill" }
        if l.contains("primary") { return "book.fill" }
        if l.contains("post-secondary") { return "building.columns.fill" }
        if l.contains("secondary") { return "books.vertical.fill" }
        return "graduationcap.fill"
    }
}

// MARK: - 4. ViewModel
class MapViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var position: MapCameraPosition = .automatic
    @Published var schools: [School] = []
    
    @Published var selectedSchool: School? {
        didSet {
            if selectedSchool != nil {
                calculateAutoRoute()
                fetchNearbyTransit()
            }
        }
    }
    
    @AppStorage("isChinese") var isChinese: Bool = false {
        didSet {
            if selectedSchool != nil {
                fetchNearbyTransit()
                calculateAutoRoute()
            }
        }
    }
    
    @AppStorage("savedHomeAddress") var savedHomeAddress: String = ""
    @AppStorage("favoriteSchoolKeys") private var favoriteSchoolKeysStorage: String = ""
    
    @Published var searchText: String = ""
    @Published var selectedDistrict: String = "All"
    @Published var selectedLevel: String = "All"
    @Published var startPoint: CLLocationCoordinate2D?
    @Published var showSettings = false
    @Published var route: MKRoute?
    @Published var travelTime: String = ""
    @Published var travelDistance: String = ""
    @Published var isCalculating = false
    @Published var nearbyMTR: String = ""
    @Published var currentUserLocation: CLLocationCoordinate2D?
    @Published var transportMode: TransportMode = .drive {
        didSet {
            if selectedSchool != nil {
                calculateAutoRoute()
            }
        }
    }
    @Published var mapDisplayMode: MapDisplayMode = .standard
    @Published var favoriteSchoolKeys: Set<String> = []
    
    private let locationManager = CLLocationManager()
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    let availableLevels = ["All", "Kindergarten", "Primary", "Secondary", "Post-Secondary"]
    
    private let districtTranslations: [String: String] = [
        "CENTRAL AND WESTERN": "中西區", "EASTERN": "東區", "ISLANDS": "離島區",
        "KOWLOON CITY": "九龍城區", "KWAI TSING": "葵青區", "KWUN TONG": "觀塘區",
        "NORTH": "北區", "SAI KUNG": "西貢區", "SHA TIN": "沙田區",
        "SHAM SHUI PO": "深水埗區", "SOUTHERN": "南區", "TAI PO": "大埔區",
        "TSUEN WAN": "荃灣區", "TUEN MUN": "屯門區", "WAN CHAI": "灣仔區",
        "WONG TAI SIN": "黃大仙區", "YAU TSIM MONG": "油尖旺區", "YUEN LONG": "元朗區"
    ]
    
    private let reverseDistrictTranslations: [String: String] = [
        "中西區": "CENTRAL AND WESTERN", "中西": "CENTRAL AND WESTERN",
        "東區": "EASTERN", "東": "EASTERN",
        "離島區": "ISLANDS", "離島": "ISLANDS",
        "九龍城區": "KOWLOON CITY", "九龍城": "KOWLOON CITY",
        "葵青區": "KWAI TSING", "葵青": "KWAI TSING",
        "觀塘區": "KWUN TONG", "觀塘": "KWUN TONG",
        "北區": "NORTH", "北": "NORTH",
        "西貢區": "SAI KUNG", "西貢": "SAI KUNG",
        "沙田區": "SHA TIN", "沙田": "SHA TIN",
        "深水埗區": "SHAM SHUI PO", "深水埗": "SHAM SHUI PO",
        "南區": "SOUTHERN", "南": "SOUTHERN",
        "大埔區": "TAI PO", "大埔": "TAI PO",
        "荃灣區": "TSUEN WAN", "荃灣": "TSUEN WAN",
        "屯門區": "TUEN MUN", "屯門": "TUEN MUN",
        "灣仔區": "WAN CHAI", "灣仔": "WAN CHAI",
        "黃大仙區": "WONG TAI SIN", "黃大仙": "WONG TAI SIN",
        "油尖旺區": "YAU TSIM MONG", "油尖旺": "YAU TSIM MONG",
        "元朗區": "YUEN LONG", "元朗": "YUEN LONG"
    ]
    
    override init() {
        super.init()
        favoriteSchoolKeys = Set(
            favoriteSchoolKeysStorage
                .split(separator: "|")
                .map { String($0) }
        )
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        
        fetchSchoolData()
        fetchHigherEducationData()
        
        if !savedHomeAddress.isEmpty {
            geocodeHomeAddress()
        }
    }
    
    // MARK: Translations
    func translateDistrict(_ dist: String) -> String {
        if dist == "All" { return isChinese ? "全部" : "All" }
        return isChinese ? (districtTranslations[dist.uppercased()] ?? dist) : dist
    }
    
    func translateLevel(_ level: String) -> String {
        if !isChinese { return level.capitalized }
        let l = level.uppercased()
        if l == "ALL" { return "全部" }
        if l.contains("KINDERGARTEN") { return "幼稚園" }
        if l.contains("PRIMARY") { return "小學" }
        if l.contains("POST-SECONDARY") { return "專上" }
        if l.contains("SECONDARY") { return "中學" }
        return level.capitalized
    }
    
    func translateFinanceType(_ type: String) -> String {
        if !isChinese { return type.capitalized }
        let t = type.uppercased()
        if t.contains("GOVERNMENT") { return "官立" }
        if t.contains("AIDED") { return "資助" }
        if t.contains("DIRECT SUBSIDY") || t.contains("直資") { return "直資 (DSS)" }
        if t.contains("PRIVATE") || t.contains("私立") { return "私立" }
        if t.contains("CAPUT") || t.contains("按位津貼") { return "按位津貼" }
        if t.contains("UGC") || t.contains("HIGHER") || t.contains("高等") { return "高等教育" }
        return type.capitalized
    }
    
    // MARK: Favorites
    private func schoolKey(_ school: School) -> String {
        "\(school.nameEN)|\(school.addressEN)"
    }
    
    func isFavorite(_ school: School) -> Bool {
        favoriteSchoolKeys.contains(schoolKey(school))
    }
    
    func toggleFavorite(_ school: School) {
        let key = schoolKey(school)
        if favoriteSchoolKeys.contains(key) {
            favoriteSchoolKeys.remove(key)
        } else {
            favoriteSchoolKeys.insert(key)
        }
        favoriteSchoolKeysStorage = favoriteSchoolKeys.joined(separator: "|")
    }
    
    var favoriteSchools: [School] {
        schools.filter { favoriteSchoolKeys.contains(schoolKey($0)) }
    }
    
    // MARK: Smart Match Score
    func smartMatchScore(for school: School) -> Int {
        // 🛠️ REFINED: Base score is lower so distance makes a bigger impact
        var score = 40
        
        // 1. Filter Matches (Up to +30)
        if selectedDistrict != "All" && school.districtEN.uppercased() == selectedDistrict.uppercased() {
            score += 15
        }
        
        if selectedLevel != "All" && school.levelEN.uppercased() == selectedLevel.uppercased() {
            score += 15
        }
        
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           matchesSearch(school, query: searchText) {
            score += 10
        }
        
        // 2. Distance Match (Massive impact on score based on physical distance)
        if let baseCoord = currentUserLocation ?? startPoint {
            let baseLocation = CLLocation(latitude: baseCoord.latitude, longitude: baseCoord.longitude)
            let schoolLocation = CLLocation(latitude: school.coordinate.latitude, longitude: school.coordinate.longitude)
            
            let distanceInKm = baseLocation.distance(from: schoolLocation) / 1000.0
            
            if distanceInKm <= 3.0 {
                score += 30 // Very close!
            } else if distanceInKm <= 8.0 {
                score += 15 // Reasonable distance
            } else if distanceInKm <= 15.0 {
                score -= 5  // Getting far
            } else if distanceInKm <= 25.0 {
                score -= 15 // Quite far
            } else {
                score -= 30 // Extremely far
            }
        }
        
        return min(max(score, 0), 100)
    }
    
    // MARK: Speech / Multimedia
    func speakSchoolInfo(_ school: School) {
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        let text: String
        if isChinese {
            text = """
            學校名稱：\(school.name(isChinese: true))。
            地址：\(school.address(isChinese: true))。
            學校類別：\(translateLevel(school.levelEN))。
            附近地鐵站：\(nearbyMTR)。
            預計時間：\(travelTime)。
            距離：\(travelDistance)。
            """
        } else {
            text = """
            School name: \(school.name(isChinese: false)).
            Address: \(school.address(isChinese: false)).
            School level: \(translateLevel(school.levelEN)).
            Nearest MTR: \(nearbyMTR).
            Estimated travel time: \(travelTime).
            Distance: \(travelDistance).
            """
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.voice = AVSpeechSynthesisVoice(language: isChinese ? "zh-HK" : "en-GB")
        speechSynthesizer.speak(utterance)
    }
    
    // MARK: Refresh / Geocode / Search
    func forceMapRefresh() {
        let refreshedSchools = schools.map { oldSchool in
            School(
                nameEN: oldSchool.nameEN,
                nameCH: oldSchool.nameCH,
                coordinate: oldSchool.coordinate,
                districtEN: oldSchool.districtEN,
                addressEN: oldSchool.addressEN,
                addressCH: oldSchool.addressCH,
                levelEN: oldSchool.levelEN,
                levelCH: oldSchool.levelCH,
                financeTypeEN: oldSchool.financeTypeEN
            )
        }
        self.schools = refreshedSchools
    }
    
    func geocodeHomeAddress() {
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = savedHomeAddress + ", Hong Kong"
        MKLocalSearch(request: searchRequest).start { response, _ in
            if let coordinate = response?.mapItems.first?.location.coordinate {
                DispatchQueue.main.async {
                    self.startPoint = coordinate
                    if self.selectedSchool != nil {
                        self.calculateAutoRoute()
                    }
                }
            }
        }
    }
    
    func fetchNearbyTransit() {
        guard let school = selectedSchool else { return }
        let request = MKLocalSearch.Request()
        request.region = MKCoordinateRegion(
            center: school.coordinate,
            latitudinalMeters: 600,
            longitudinalMeters: 600
        )
        
        request.naturalLanguageQuery = isChinese ? "地鐵站" : "MTR Station"
        MKLocalSearch(request: request).start { response, _ in
            DispatchQueue.main.async {
                self.nearbyMTR = response?.mapItems.first?.name ?? (self.isChinese ? "無" : "None")
            }
        }
    }
    
    func calculateAutoRoute() {
        guard let start = startPoint, let end = selectedSchool else { return }
        
        if transportMode == .transit {
            DispatchQueue.main.async {
                self.isCalculating = false
                self.route = nil
                self.travelTime = self.isChinese ? "查看 Apple Maps" : "Check Maps"
                self.travelDistance = "--"
            }
            return
        }
        
        isCalculating = true
        
        let request = MKDirections.Request()
        
        let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        request.source = MKMapItem(location: startLoc, address: nil)
        
        let endLoc = CLLocation(latitude: end.coordinate.latitude, longitude: end.coordinate.longitude)
        request.destination = MKMapItem(location: endLoc, address: nil)
        
        request.transportType = transportMode.type
        
        MKDirections(request: request).calculate { response, _ in
            DispatchQueue.main.async {
                self.isCalculating = false
                if let route = response?.routes.first {
                    self.route = route
                    let finalTime = route.expectedTravelTime
                    
                    self.travelTime = "\(Int(finalTime / 60)) \(self.isChinese ? "分鐘" : "mins")"
                    self.travelDistance = String(format: "%.1f km", route.distance / 1000)
                } else {
                    self.route = nil
                    self.travelTime = "--"
                    self.travelDistance = "--"
                }
            }
        }
    }
    
    var filteredSchools: [School] {
        let cleanSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if selectedDistrict == "All" && selectedLevel == "All" && cleanSearch.isEmpty {
            if let selected = selectedSchool {
                return [selected]
            }
            return []
        }
        
        var result = schools
        
        if selectedDistrict != "All" {
            result = result.filter { $0.districtEN.uppercased() == selectedDistrict.uppercased() }
        }
        
        if selectedLevel != "All" {
            result = result.filter { $0.levelEN.uppercased() == selectedLevel.uppercased() }
        }
        
        if !cleanSearch.isEmpty {
            result = result.filter { matchesSearch($0, query: cleanSearch) }
        }
        
        return result
    }
    
    var availableDistricts: [String] {
        let districts = Set(schools.map { $0.districtEN.uppercased() })
            .filter { !$0.isEmpty && $0 != "VARIOUS" } // 🛠️ FIXED: Filters out "VARIOUS"
        return ["All"] + Array(districts).sorted()
    }
    
    private func normalizeForSearch(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "　", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
    
    private func matchesSearch(_ school: School, query: String) -> Bool {
        let normalizedQuery = normalizeForSearch(query)
        let normalizedSchoolText = normalizeForSearch(school.searchableText)
        
        if normalizedSchoolText.contains(normalizedQuery) {
            return true
        }
        
        let simplifiedQuery = query.applyingTransform(.toLatin, reverse: false) ?? query
        let normalizedSimplifiedQuery = normalizeForSearch(simplifiedQuery)
        
        return normalizedSchoolText.contains(normalizedSimplifiedQuery)
    }
    
    // MARK: Location
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            manager.requestLocation()
        case .denied, .restricted:
            print("❌ Location permission denied")
        case .notDetermined:
            print("⌛ Location permission not determined")
        @unknown default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("✅ 获取到位置：\(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        DispatchQueue.main.async {
            self.currentUserLocation = location.coordinate
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location update failed: \(error.localizedDescription)")
    }
    
    // MARK: Data Parsing
    private func parseCoord(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let s = value as? String { return Double(s) ?? 0 }
        return 0
    }
    
    // MARK: API 1 - Fetch K-12 Data
    func fetchSchoolData() {
        guard let url = URL(string: "https://www.edb.gov.hk/attachment/en/student-parents/sch-info/sch-search/sch-location-info/SCH_LOC_EDB.json") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let mappedK12 = json.compactMap { item -> School? in
                    
                    let lat = self.parseCoord(item["LATITUDE"] ?? item["緯度"])
                    let lon = self.parseCoord(item["LONGITUDE"] ?? item["經度"])
                    guard lat != 0 else { return nil }
                    
                    let nameEN = (item["ENGLISH NAME"] as? String) ?? (item["英文名稱"] as? String) ?? (item["NAME_ENG"] as? String) ?? ""
                    let nameCH = (item["CHINESE NAME"] as? String) ?? (item["中文名稱"] as? String) ?? (item["NAME_CHI"] as? String) ?? ""
                    let addrEN = (item["ENGLISH ADDRESS"] as? String) ?? (item["英文地址"] as? String) ?? ""
                    let addrCH = (item["CHINESE ADDRESS"] as? String) ?? (item["中文地址"] as? String) ?? ""
                    
                    let rawDist = ((item["DISTRICT"] as? String) ?? (item["分區"] as? String) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let safeDistEN = self.reverseDistrictTranslations[rawDist] ?? rawDist
                    
                    let rawLvl = (item["SCHOOL LEVEL"] as? String) ?? (item["學校類別"] as? String) ?? ""
                    var safeLvlEN = rawLvl
                    if rawLvl.contains("幼稚園") {
                        safeLvlEN = "KINDERGARTEN"
                    } else if rawLvl.contains("小學") {
                        safeLvlEN = "PRIMARY"
                    } else if rawLvl.contains("中學") {
                        safeLvlEN = "SECONDARY"
                    }
                    
                    return School(
                        nameEN: nameEN.isEmpty ? nameCH : nameEN,
                        nameCH: nameCH.isEmpty ? nameEN : nameCH,
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        districtEN: safeDistEN,
                        addressEN: addrEN.isEmpty ? addrCH : addrEN,
                        addressCH: addrCH.isEmpty ? addrEN : addrCH,
                        levelEN: safeLvlEN,
                        levelCH: "",
                        financeTypeEN: (item["FINANCE TYPE"] as? String) ?? (item["資助種類"] as? String) ?? ""
                    )
                }
                
                DispatchQueue.main.async {
                    self.schools.append(contentsOf: mappedK12)
                }
            }
        }.resume()
    }
    
    // MARK: API 2 - Fetch Post-Secondary Data
    func fetchHigherEducationData() {
        guard let url = URL(string: "https://portal.csdi.gov.hk/server/services/common/edb_rcd_1629267205213_58940/MapServer/WFSServer?service=wfs&request=GetFeature&typenames=ASFPS&outputFormat=geojson&startIndex=0") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            
            let fallbackUniversities = [
                School(nameEN: "Hong Kong Metropolitan University", nameCH: "香港都會大學", coordinate: CLLocationCoordinate2D(latitude: 22.3162, longitude: 114.1803), districtEN: "KOWLOON CITY", addressEN: "Good Shepherd Street, Ho Man Tin", addressCH: "何文田牧愛街", levelEN: "Post-Secondary", levelCH: "專上", financeTypeEN: "Self-financing"),
                School(nameEN: "The University of Hong Kong", nameCH: "香港大學", coordinate: CLLocationCoordinate2D(latitude: 22.2830, longitude: 114.1371), districtEN: "CENTRAL AND WESTERN", addressEN: "Pok Fu Lam", addressCH: "薄扶林", levelEN: "Post-Secondary", levelCH: "專上", financeTypeEN: "UGC-funded"),
                School(nameEN: "The Chinese University of Hong Kong", nameCH: "香港中文大學", coordinate: CLLocationCoordinate2D(latitude: 22.4195, longitude: 114.2070), districtEN: "SHA TIN", addressEN: "Ma Liu Shui", addressCH: "馬料水", levelEN: "Post-Secondary", levelCH: "專上", financeTypeEN: "UGC-funded"),
                School(nameEN: "The Hong Kong University of Science and Technology", nameCH: "香港科技大學", coordinate: CLLocationCoordinate2D(latitude: 22.3364, longitude: 114.2655), districtEN: "SAI KUNG", addressEN: "Clear Water Bay", addressCH: "清水灣", levelEN: "Post-Secondary", levelCH: "專上", financeTypeEN: "UGC-funded"),
                School(nameEN: "The Hong Kong Polytechnic University", nameCH: "香港理工大學", coordinate: CLLocationCoordinate2D(latitude: 22.3040, longitude: 114.1798), districtEN: "YAU TSIM MONG", addressEN: "Hung Hom", addressCH: "紅磡", levelEN: "Post-Secondary", levelCH: "專上", financeTypeEN: "UGC-funded"),
                School(nameEN: "City University of Hong Kong", nameCH: "香港城市大學", coordinate: CLLocationCoordinate2D(latitude: 22.3360, longitude: 114.1725), districtEN: "SHAM SHUI PO", addressEN: "Tat Chee Avenue, Kowloon Tong", addressCH: "九龍塘達之路", levelEN: "Post-Secondary", levelCH: "專上", financeTypeEN: "UGC-funded")
            ]
            
            var apiSuccess = false
            
            if let data = data,
               error == nil,
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                do {
                    let decoded = try JSONSerialization.jsonObject(with: data)
                    var itemsToParse: [[String: Any]] = []
                    
                    if let jsonDict = decoded as? [String: Any],
                       let features = jsonDict["features"] as? [[String: Any]] {
                        itemsToParse = features
                    }
                    
                    if !itemsToParse.isEmpty {
                        apiSuccess = true
                        let mapped = itemsToParse.compactMap { item -> School? in
                            let props = (item["properties"] as? [String: Any]) ?? [:]
                            
                            var lat: Double = 0
                            var lon: Double = 0
                            
                            if let geom = item["geometry"] as? [String: Any],
                               let coords = geom["coordinates"] as? [Double],
                               coords.count >= 2 {
                                lat = coords[1]
                                lon = coords[0]
                            } else {
                                lat = self.parseCoord(props["Latitude___緯度"])
                                lon = self.parseCoord(props["Longitude___經度"])
                            }
                            
                            guard lat != 0 else { return nil }
                            
                            let nameEN = (props["Facility_Name"] as? String) ?? "Institution"
                            let nameCH = (props["設施名稱"] as? String) ?? nameEN
                            
                            return School(
                                nameEN: nameEN.isEmpty ? "Institution" : nameEN,
                                nameCH: nameCH.isEmpty ? nameEN : nameCH,
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                districtEN: "Various",
                                addressEN: (props["Address"] as? String) ?? "Contact Institution",
                                addressCH: (props["地址"] as? String) ?? "請聯絡院校",
                                levelEN: "Post-Secondary",
                                levelCH: "專上",
                                financeTypeEN: "Higher Education"
                            )
                        }
                        
                        DispatchQueue.main.async {
                            self.schools.append(contentsOf: mapped)
                        }
                    }
                } catch {
                    print("JSON decode failed.")
                }
            }
            
            if !apiSuccess {
                DispatchQueue.main.async {
                    self.schools.append(contentsOf: fallbackUniversities)
                }
            }
        }.resume()
    }
}

// MARK: - 5. UI Components
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                action()
            }
        }) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: isSelected ? [Color.blue, Color.cyan] : [Color(.systemBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
                .shadow(color: isSelected ? .blue.opacity(0.25) : .black.opacity(0.05), radius: 4, y: 2)
                .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

struct MiniStatCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(tint)
                .font(.headline)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value.isEmpty ? "--" : value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

struct FavoriteStrip: View {
    @ObservedObject var viewModel: MapViewModel
    
    var body: some View {
        if !viewModel.favoriteSchools.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.favoriteSchools, id: \.id) { school in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.selectedSchool = school
                                viewModel.position = .region(
                                    MKCoordinateRegion(
                                        center: school.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                                    )
                                )
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.pink)
                                Text(school.name(isChinese: viewModel.isChinese))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.systemBackground).opacity(0.95))
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: MapViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section(viewModel.isChinese ? "語言設定" : "Language Settings") {
                    Toggle(viewModel.isChinese ? "繁體中文" : "Traditional Chinese", isOn: $viewModel.isChinese)
                        .onChange(of: viewModel.isChinese) { _ in
                            viewModel.forceMapRefresh()
                            if viewModel.selectedSchool != nil {
                                viewModel.fetchNearbyTransit()
                                viewModel.calculateAutoRoute()
                            }
                        }
                }
                
                Section(viewModel.isChinese ? "地圖樣式" : "Map Style") {
                    Picker("Map", selection: $viewModel.mapDisplayMode) {
                        ForEach(MapDisplayMode.allCases, id: \.self) { mode in
                            Label(mode.label(isChinese: viewModel.isChinese), systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section(viewModel.isChinese ? "起點地址" : "Home Location") {
                    TextField(viewModel.isChinese ? "輸入香港地址" : "Enter HK address", text: $viewModel.savedHomeAddress)
                    Button(viewModel.isChinese ? "儲存" : "Save") {
                        viewModel.geocodeHomeAddress()
                        dismiss()
                    }
                    .disabled(viewModel.savedHomeAddress.isEmpty)
                }
            }
            .navigationTitle(viewModel.isChinese ? "設定" : "Settings")
            .toolbar {
                Button(viewModel.isChinese ? "完成" : "Done") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - 6. Main ContentView
struct ContentView: View {
    @StateObject private var viewModel = MapViewModel()
    @State private var animateSelectionCard = false
    
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        ZStack(alignment: .top) {
            mapView
            topOverlay
            bottomCardOverlay
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: viewModel.selectedSchool?.id)
        .animation(.easeInOut(duration: 0.25), value: viewModel.favoriteSchools.count)
        .animation(.easeInOut(duration: 0.2), value: viewModel.searchText)
    }
    
    // MARK: Map View
    private var mapView: some View {
        Map(position: $viewModel.position, selection: $viewModel.selectedSchool) {
            if let start = viewModel.startPoint {
                Annotation(viewModel.isChinese ? "起點" : "Home", coordinate: start) {
                    Image(systemName: "house.fill")
                        .padding(10)
                        .background(.blue)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
            }
            
            if let route = viewModel.route {
                MapPolyline(route.polyline)
                    .stroke(.blue, lineWidth: 5)
            }
            
            ForEach(viewModel.filteredSchools, id: \.id) { school in
                Marker(
                    school.name(isChinese: viewModel.isChinese),
                    systemImage: school.mapIcon,
                    coordinate: school.coordinate
                )
                .tint(colorForLevel(school.levelEN))
                .tag(school)
            }
        }
        .mapStyle(currentMapStyle)
        .edgesIgnoringSafeArea(.all)
    }
    
    private var currentMapStyle: MapStyle {
        switch viewModel.mapDisplayMode {
        case .standard:
            return .standard(elevation: .realistic)
        case .hybrid:
            return .hybrid(elevation: .realistic)
        case .imagery:
            return .imagery(elevation: .realistic)
        }
    }
    
    // MARK: Top Overlay
    private var topOverlay: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                headerBar
                searchBar
                searchResultsList
                levelFilterRow
                districtFilterRow
                FavoriteStrip(viewModel: viewModel)
            }
            .padding(.top, 8)
            .padding(.bottom, 14)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.28),
                        Color.black.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            Spacer()
        }
    }
    
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.isChinese ? "學校探索地圖" : "School Explorer")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(viewModel.isChinese ? "搜尋、比較、導航" : "Search, match and navigate")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
            }
            
            Spacer()
            
            Button {
                viewModel.showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(.ultraThinMaterial.opacity(0.95))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField(viewModel.isChinese ? "搜尋學校..." : "Search schools...", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .focused($isSearchFocused)
                
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                        isSearchFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .transition(.scale)
                }
            }
            .padding(12)
            .background(Color(.systemBackground).opacity(0.96))
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            
            Menu {
                ForEach(MapDisplayMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.mapDisplayMode = mode
                        }
                    } label: {
                        Label(mode.label(isChinese: viewModel.isChinese), systemImage: mode.icon)
                    }
                }
            } label: {
                Image(systemName: viewModel.mapDisplayMode.icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .padding(12)
                    .background(Color(.systemBackground).opacity(0.96))
                    .cornerRadius(14)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var searchResultsList: some View {
        if isSearchFocused && !viewModel.searchText.isEmpty {
            let suggestions = Array(viewModel.filteredSchools.prefix(6))
            
            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { school in
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            isSearchFocused = false
                            
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.selectedSchool = school
                                viewModel.position = .region(
                                    MKCoordinateRegion(
                                        center: school.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    )
                                )
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(colorForLevel(school.levelEN))
                                    .font(.title3)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(school.name(isChinese: viewModel.isChinese))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    Text(school.address(isChinese: viewModel.isChinese))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color(.systemBackground).opacity(0.98))
                        }
                        .buttonStyle(.plain)
                        
                        if school.id != suggestions.last?.id {
                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                }
                .background(Color(.systemBackground).opacity(0.98))
                .cornerRadius(14)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
                .padding(.horizontal)
                .padding(.top, -4)
            }
        }
    }
    
    private var levelFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(viewModel.availableLevels, id: \.self) { level in
                    FilterChip(
                        title: viewModel.translateLevel(level),
                        isSelected: viewModel.selectedLevel == level
                    ) {
                        viewModel.selectedLevel = level
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var districtFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(viewModel.availableDistricts, id: \.self) { dist in
                    FilterChip(
                        title: viewModel.translateDistrict(dist),
                        isSelected: viewModel.selectedDistrict == dist
                    ) {
                        viewModel.selectedDistrict = dist
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: Bottom Card Overlay
    private var bottomCardOverlay: some View {
        Group {
            if let school = viewModel.selectedSchool {
                VStack {
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 14) {
                        schoolHeader(school)
                        highlightInfoBox(school)
                        scoreAndActionsRow(school)
                        transportPicker
                        statsRow
                        actionButtons(school)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
                    )
                    .padding()
                    .scaleEffect(animateSelectionCard ? 1.0 : 0.96)
                    .opacity(animateSelectionCard ? 1.0 : 0.0)
                    .onAppear {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            animateSelectionCard = true
                        }
                    }
                    .onDisappear {
                        animateSelectionCard = false
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private func schoolHeader(_ school: School) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(colorForLevel(school.levelEN).opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: school.mapIcon)
                    .foregroundColor(colorForLevel(school.levelEN))
                    .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(school.name(isChinese: viewModel.isChinese))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 6) {
                    Text(viewModel.translateLevel(school.levelEN))
                        .font(.caption)
                        .bold()
                        .foregroundColor(colorForLevel(school.levelEN))
                    
                    if !school.financeTypeEN.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(viewModel.translateFinanceType(school.financeTypeEN))
                            .font(.caption)
                            .bold()
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Button {
                withAnimation(.spring()) {
                    viewModel.selectedSchool = nil
                    viewModel.route = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func highlightInfoBox(_ school: School) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(school.address(isChinese: viewModel.isChinese), systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Label(
                viewModel.isChinese
                    ? "最近地鐵站: \(viewModel.nearbyMTR)"
                    : "Nearest MTR: \(viewModel.nearbyMTR)",
                systemImage: "tram.fill"
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.08), Color.cyan.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
    }
    
    private func scoreAndActionsRow(_ school: School) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.18), lineWidth: 8)
                        .frame(width: 56, height: 56)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(viewModel.smartMatchScore(for: school)) / 100.0)
                        .stroke(
                            LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 56, height: 56)
                    
                    Text("\(viewModel.smartMatchScore(for: school))")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.isChinese ? "智能匹配分" : "Smart Match")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(viewModel.isChinese ? "依搜尋條件及路線評估" : "Based on filters and route")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) {
                    viewModel.toggleFavorite(school)
                }
            } label: {
                Image(systemName: viewModel.isFavorite(school) ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundColor(viewModel.isFavorite(school) ? .pink : .secondary)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
                    .scaleEffect(viewModel.isFavorite(school) ? 1.12 : 1.0)
            }
            .buttonStyle(.plain)
            
            Button {
                viewModel.speakSchoolInfo(school)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
    
    private var transportPicker: some View {
        Picker("Mode", selection: $viewModel.transportMode) {
            ForEach(TransportMode.allCases, id: \.self) { mode in
                Label(mode.label(isChinese: viewModel.isChinese), systemImage: mode.rawValue)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var statsRow: some View {
        HStack(spacing: 10) {
            if viewModel.isCalculating {
                MiniStatCard(
                    title: viewModel.isChinese ? "路線" : "Route",
                    value: viewModel.isChinese ? "計算中..." : "Calculating...",
                    icon: "clock.arrow.circlepath",
                    tint: .blue
                )
                
                MiniStatCard(
                    title: viewModel.isChinese ? "距離" : "Distance",
                    value: "--",
                    icon: "point.topleft.down.curvedto.point.bottomright.up",
                    tint: .cyan
                )
            } else {
                MiniStatCard(
                    title: viewModel.isChinese ? "時間" : "Time",
                    value: viewModel.travelTime,
                    icon: "clock.fill",
                    tint: .blue
                )
                
                MiniStatCard(
                    title: viewModel.isChinese ? "距離" : "Distance",
                    value: viewModel.travelDistance,
                    icon: "arrow.triangle.turn.up.right.diamond.fill",
                    tint: .cyan
                )
            }
        }
    }
    
    private func actionButtons(_ school: School) -> some View {
        VStack(spacing: 10) {
            Button {
                print("当前用户位置：\(String(describing: viewModel.currentUserLocation))")
                print("当前Home地址坐标：\(String(describing: viewModel.startPoint))")

                let sourceCoordinate: CLLocationCoordinate2D

                if let userCoord = viewModel.currentUserLocation {
                    sourceCoordinate = userCoord
                } else if let homeCoord = viewModel.startPoint {
                    sourceCoordinate = homeCoord
                } else {
                    print("❌ 没有真实定位，也没有Home地址坐标，无法导航")
                    return
                }

                let startLoc = CLLocation(latitude: sourceCoordinate.latitude, longitude: sourceCoordinate.longitude)
                let sourceItem = MKMapItem(location: startLoc, address: nil)
                sourceItem.name = viewModel.isChinese ? "我的位置" : "My Location"
                
                let endLoc = CLLocation(latitude: school.coordinate.latitude, longitude: school.coordinate.longitude)
                let destinationItem = MKMapItem(location: endLoc, address: nil)
                destinationItem.name = school.name(isChinese: viewModel.isChinese)
                
                let modeKey = viewModel.transportMode == .drive
                    ? MKLaunchOptionsDirectionsModeDriving
                    : (viewModel.transportMode == .walk
                        ? MKLaunchOptionsDirectionsModeWalking
                        : MKLaunchOptionsDirectionsModeTransit)
                
                MKMapItem.openMaps(
                    with: [sourceItem, destinationItem],
                    launchOptions: [MKLaunchOptionsDirectionsModeKey: modeKey]
                )
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                    Text(viewModel.isChinese ? "開始導航" : "Start Navigation")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
            
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.position = .region(
                        MKCoordinateRegion(
                            center: school.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    )
                }
            } label: {
                HStack {
                    Image(systemName: "scope")
                    Text(viewModel.isChinese ? "聚焦學校位置" : "Focus on School")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .foregroundColor(.primary)
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: Helpers
    func colorForLevel(_ level: String) -> Color {
        let l = level.lowercased()
        if l.contains("kindergarten") { return .purple }
        if l.contains("primary") { return .green }
        if l.contains("post-secondary") { return .orange }
        if l.contains("secondary") { return .blue }
        return .red
    }
}
