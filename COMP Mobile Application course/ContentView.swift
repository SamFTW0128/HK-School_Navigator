import SwiftUI
import MapKit
import Combine
import CoreLocation

// 1. Transport Types Enum
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

// 2. Data Model
struct School: Identifiable, Hashable {
    let id = UUID() // The secret to forcing the map to redraw instantly!
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
    
    var mapIcon: String {
        let l = levelEN.lowercased()
        if l.contains("kindergarten") { return "teddybear.fill" }
        if l.contains("primary") { return "book.fill" }
        if l.contains("secondary") { return "books.vertical.fill" }
        if l.contains("post-secondary") { return "building.columns.fill" }
        return "graduationcap.fill"
    }
}

// 3. ViewModel
class MapViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var position: MapCameraPosition = .automatic
    @Published var schools: [School] = []
    
    @Published var selectedSchool: School? {
        didSet { if selectedSchool != nil { calculateAutoRoute(); fetchNearbyTransit() } }
    }
    
    @AppStorage("isChinese") var isChinese: Bool = false {
        didSet { if selectedSchool != nil { fetchNearbyTransit(); calculateAutoRoute() } }
    }
    @AppStorage("savedHomeAddress") var savedHomeAddress: String = ""
    
    @Published var searchText: String = ""
    @Published var selectedDistrict: String = "All"
    @Published var selectedLevel: String = "All"
    
    @Published var startPoint: CLLocationCoordinate2D?
    @Published var showSettings = false
    
    @Published var transportMode: TransportMode = .drive {
        didSet { if selectedSchool != nil { calculateAutoRoute() } }
    }
    @Published var route: MKRoute?
    @Published var travelTime: String = ""
    @Published var travelDistance: String = ""
    @Published var isCalculating = false
    @Published var nearbyMTR: String = ""
    
    private let locationManager = CLLocationManager()
    
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
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        
        // Only load the data from the network exactly ONCE at startup
        fetchSchoolData()
        fetchHigherEducationData()
        if !savedHomeAddress.isEmpty { geocodeHomeAddress() }
    }
    
    // THE MASTER FIX: Bypasses the Apple Maps rendering bug without hitting the network
    func forceMapRefresh() {
        let refreshedSchools = schools.map { oldSchool in
            School(
                nameEN: oldSchool.nameEN, nameCH: oldSchool.nameCH,
                coordinate: oldSchool.coordinate, districtEN: oldSchool.districtEN,
                addressEN: oldSchool.addressEN, addressCH: oldSchool.addressCH,
                levelEN: oldSchool.levelEN, levelCH: oldSchool.levelCH,
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
                    if self.selectedSchool != nil { self.calculateAutoRoute() }
                }
            }
        }
    }

    func fetchNearbyTransit() {
        guard let school = selectedSchool else { return }
        let request = MKLocalSearch.Request()
        request.region = MKCoordinateRegion(center: school.coordinate, latitudinalMeters: 600, longitudinalMeters: 600)
        
        request.naturalLanguageQuery = isChinese ? "地鐵站" : "MTR Station"
        MKLocalSearch(request: request).start { response, _ in
            DispatchQueue.main.async { self.nearbyMTR = response?.mapItems.first?.name ?? (self.isChinese ? "無" : "None") }
        }
    }
    
    func calculateAutoRoute() {
        guard let start = startPoint, let end = selectedSchool else { return }
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
                    var finalTime = route.expectedTravelTime
                    
                    if self.transportMode == .transit { finalTime += 900 }
                    else if self.transportMode == .walk { finalTime *= 4 }
                    
                    self.travelTime = "\(Int(finalTime / 60)) \(self.isChinese ? "分鐘" : "mins")"
                    self.travelDistance = String(format: "%.1f km", route.distance / 1000)
                }
            }
        }
    }
    
    var filteredSchools: [School] {
        var result = schools
        if selectedDistrict != "All" { result = result.filter { $0.districtEN.uppercased() == selectedDistrict.uppercased() } }
        if selectedLevel != "All" { result = result.filter { $0.levelEN.localizedCaseInsensitiveContains(selectedLevel) } }
        if !searchText.isEmpty {
            result = result.filter { $0.nameEN.localizedCaseInsensitiveContains(searchText) || $0.nameCH.localizedCaseInsensitiveContains(searchText) }
        }
        return (selectedDistrict == "All" && selectedLevel == "All" && searchText.isEmpty) ? Array(result.prefix(150)) : result
    }
    
    var availableDistricts: [String] {
        let districts = Set(schools.map { $0.districtEN.uppercased() }).filter { !$0.isEmpty }
        return ["All"] + Array(districts).sorted()
    }
    
    private func parseCoord(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let s = value as? String { return Double(s) ?? 0 }
        return 0
    }
    
    // -----------------------------------------------------------------
    // API 1: Fetch K-12 Data (Strictly the stable /en/ URL)
    // -----------------------------------------------------------------
    func fetchSchoolData() {
        guard let url = URL(string: "https://www.edb.gov.hk/attachment/en/student-parents/sch-info/sch-search/sch-location-info/SCH_LOC_EDB.json") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let mappedK12 = json.compactMap { item -> School? in
                    
                    let lat = self.parseCoord(item["LATITUDE"] ?? item["緯度"])
                    let lon = self.parseCoord(item["LONGITUDE"] ?? item["經度"])
                    guard lat != 0 else { return nil }
                    
                    // THE FIX: Aggressively search for the Chinese name across multiple possible EDB keys
                    let nameEN = (item["ENGLISH NAME"] as? String) ?? (item["英文名稱"] as? String) ?? (item["NAME_ENG"] as? String) ?? ""
                    let nameCH = (item["CHINESE NAME"] as? String) ?? (item["中文名稱"] as? String) ?? (item["NAME_CHI"] as? String) ?? ""
                    let addrEN = (item["ENGLISH ADDRESS"] as? String) ?? (item["英文地址"] as? String) ?? ""
                    let addrCH = (item["CHINESE ADDRESS"] as? String) ?? (item["中文地址"] as? String) ?? ""
                    
                    let rawDist = ((item["DISTRICT"] as? String) ?? (item["分區"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let safeDistEN = self.reverseDistrictTranslations[rawDist] ?? rawDist
                    
                    let rawLvl = (item["SCHOOL LEVEL"] as? String) ?? (item["學校類別"] as? String) ?? ""
                    var safeLvlEN = rawLvl
                    if rawLvl.contains("幼稚園") { safeLvlEN = "KINDERGARTEN" }
                    else if rawLvl.contains("小學") { safeLvlEN = "PRIMARY" }
                    else if rawLvl.contains("中學") { safeLvlEN = "SECONDARY" }
                    
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
    
    // -----------------------------------------------------------------
    // API 2: Fetch Post-Secondary Data
    // -----------------------------------------------------------------
    func fetchHigherEducationData() {
        guard let url = URL(string: "https://api.csdi.gov.hk/apim/datahub/v1/records?datasetId=edb_rcd_1629267205213_58940") else { return }
        
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
            
            if let data = data, error == nil, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                do {
                    let decoded = try JSONSerialization.jsonObject(with: data)
                    var itemsToParse: [[String: Any]] = []
                    
                    if let jsonDict = decoded as? [String: Any] {
                        itemsToParse = (jsonDict["records"] as? [[String: Any]]) ?? (jsonDict["features"] as? [[String: Any]]) ?? []
                    } else if let jsonArray = decoded as? [[String: Any]] {
                        itemsToParse = jsonArray
                    }
                    
                    if !itemsToParse.isEmpty {
                        apiSuccess = true
                        let mapped = itemsToParse.compactMap { item -> School? in
                            let props = (item["properties"] as? [String: Any]) ?? item
                            
                            var lat: Double = 0; var lon: Double = 0
                            
                            if let geom = item["geometry"] as? [String: Any], let coords = geom["coordinates"] as? [Double], coords.count >= 2 {
                                lat = coords[1]; lon = coords[0]
                            } else {
                                lat = self.parseCoord(props["LATITUDE"])
                                lon = self.parseCoord(props["LONGITUDE"])
                            }
                            
                            guard lat != 0 else { return nil }
                            let nameEN = (props["ENGLISH NAME"] as? String) ?? (props["School_Name_Eng"] as? String) ?? ""
                            let nameCH = (props["CHINESE NAME"] as? String) ?? (props["School_Name_Chi"] as? String) ?? ""
                            
                            return School(
                                nameEN: nameEN.isEmpty ? "Institution" : nameEN,
                                nameCH: nameCH.isEmpty ? nameEN : nameCH,
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                districtEN: ((props["DISTRICT"] as? String) ?? "Various").trimmingCharacters(in: .whitespacesAndNewlines),
                                addressEN: (props["ENGLISH ADDRESS"] as? String) ?? "Contact Institution",
                                addressCH: (props["CHINESE ADDRESS"] as? String) ?? "請聯絡院校",
                                levelEN: "Post-Secondary", levelCH: "專上", financeTypeEN: "Higher Education"
                            )
                        }
                        DispatchQueue.main.async { self.schools.append(contentsOf: mapped) }
                    }
                } catch { print("JSON decode failed.") }
            }
            
            if !apiSuccess {
                DispatchQueue.main.async { self.schools.append(contentsOf: fallbackUniversities) }
            }
        }.resume()
    }
}

// 4. UI Components
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .bold)).padding(.horizontal, 14).padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.systemBackground)).foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(10).shadow(radius: 1)
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
                        .onChange(of: viewModel.isChinese) {
                            // FAST, ZERO-NETWORK REFRESH: Instantly redraws the map markers in the new language!
                            viewModel.forceMapRefresh()
                            if viewModel.selectedSchool != nil {
                                viewModel.fetchNearbyTransit()
                                viewModel.calculateAutoRoute()
                            }
                        }
                }
                Section(viewModel.isChinese ? "起點地址" : "Home Location") {
                    TextField(viewModel.isChinese ? "輸入香港地址" : "Enter HK address", text: $viewModel.savedHomeAddress)
                    Button(viewModel.isChinese ? "儲存" : "Save") { viewModel.geocodeHomeAddress(); dismiss() }
                        .disabled(viewModel.savedHomeAddress.isEmpty)
                }
            }
            .navigationTitle(viewModel.isChinese ? "設定" : "Settings")
            .toolbar { Button(viewModel.isChinese ? "完成" : "Done") { dismiss() } }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = MapViewModel()
    
    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $viewModel.position, selection: $viewModel.selectedSchool) {
                if let start = viewModel.startPoint {
                    Annotation(viewModel.isChinese ? "起點" : "Home", coordinate: start) {
                        Image(systemName: "house.fill").padding(8).background(.blue).foregroundColor(.white).clipShape(Circle())
                    }
                }
                if let route = viewModel.route { MapPolyline(route.polyline).stroke(.blue, lineWidth: 5) }
                
                ForEach(viewModel.filteredSchools, id: \.id) { school in
                    Marker(school.name(isChinese: viewModel.isChinese), systemImage: school.mapIcon, coordinate: school.coordinate)
                        .tint(colorForLevel(school.levelEN)).tag(school)
                }
            }
            .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                            TextField(viewModel.isChinese ? "搜尋學校..." : "Search schools...", text: $viewModel.searchText)
                        }
                        .padding(10).background(.background).cornerRadius(10)
                        
                        Button { viewModel.showSettings = true } label: {
                            Image(systemName: "gearshape.fill").font(.title2).foregroundColor(.blue).padding(8).background(.background).cornerRadius(10)
                        }
                    }.padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(viewModel.availableLevels, id: \.self) { level in
                                FilterChip(title: viewModel.translateLevel(level), isSelected: viewModel.selectedLevel == level) { viewModel.selectedLevel = level }
                            }
                        }.padding(.horizontal)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(viewModel.availableDistricts, id: \.self) { dist in
                                FilterChip(title: viewModel.translateDistrict(dist), isSelected: viewModel.selectedDistrict == dist) { viewModel.selectedDistrict = dist }
                            }
                        }.padding(.horizontal)
                    }
                }.padding(.vertical, 10).background(.ultraThinMaterial)
                Spacer()
            }
            
            if let school = viewModel.selectedSchool {
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(school.name(isChinese: viewModel.isChinese))
                                    .font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                HStack(spacing: 6) {
                                    Text(viewModel.translateLevel(school.levelEN))
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(colorForLevel(school.levelEN))
                                    
                                    if !school.financeTypeEN.isEmpty {
                                        Text("•").font(.caption).foregroundColor(.secondary)
                                        Text(viewModel.translateFinanceType(school.financeTypeEN))
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            Button { viewModel.selectedSchool = nil; viewModel.route = nil } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.title2)
                            }
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label(school.address(isChinese: viewModel.isChinese), systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Label(viewModel.isChinese ? "最近地鐵站: \(viewModel.nearbyMTR)" : "Nearest MTR: \(viewModel.nearbyMTR)", systemImage: "tram.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        
                        Picker("Mode", selection: $viewModel.transportMode) {
                            ForEach(TransportMode.allCases, id: \.self) { mode in
                                Label(mode.label(isChinese: viewModel.isChinese), systemImage: mode.rawValue).tag(mode)
                            }
                        }.pickerStyle(.segmented)
                        
                        HStack {
                            if viewModel.isCalculating {
                                ProgressView()
                                Text(viewModel.isChinese ? " 計算中..." : " Calculating...")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            else {
                                Label(viewModel.travelTime, systemImage: "clock.fill")
                                Label(viewModel.travelDistance, systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            }
                        }.font(.subheadline).bold().foregroundColor(.blue)
                        
                        Button {
                            let loc = CLLocation(latitude: school.coordinate.latitude, longitude: school.coordinate.longitude)
                            let mapItem = MKMapItem(location: loc, address: nil)
                            mapItem.name = school.name(isChinese: viewModel.isChinese)
                            let modeKey = viewModel.transportMode == .drive ? MKLaunchOptionsDirectionsModeDriving : (viewModel.transportMode == .walk ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeTransit)
                            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: modeKey])
                        } label: {
                            Text(viewModel.isChinese ? "開始導航" : "Start Navigation").frame(maxWidth: .infinity).padding().background(.blue).foregroundColor(.white).cornerRadius(12)
                        }
                    }
                    .padding().background(Color(.systemBackground)).cornerRadius(20).shadow(radius: 10).padding()
                }
            }
        }
        .sheet(isPresented: $viewModel.showSettings) { SettingsView(viewModel: viewModel) }
    }
    
    func colorForLevel(_ level: String) -> Color {
        let l = level.lowercased()
        if l.contains("kindergarten") { return .purple }
        if l.contains("primary") { return .green }
        if l.contains("secondary") { return .blue }
        if l.contains("post-secondary") { return .orange }
        return .red
    }
}
