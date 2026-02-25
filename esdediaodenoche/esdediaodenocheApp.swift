import AVFoundation
import Combine  // Para ObservableObject y @Published
import CoreLocation
import Foundation
import SwiftUI
import UIKit  // Para interpolación de colores

// MARK: - Constantes y Estructuras para Cálculo Solar
private let SOLAR_DEGREES_PER_HOUR = 15.0

enum Zenith: Double {
    case official = 90.8333333333
    case civil = 96.0
    case nautical = 102.0
    case astronomical = 108.0
}

struct Sun {
    let dayOfYear: Double

    var longitude: Double {
        let solarMeanAnomaly = (0.9856 * dayOfYear) - 3.289
        let solarLongitudeApprox =
            solarMeanAnomaly + (1.916 * sin(solarMeanAnomaly.radians))
            + (0.020 * sin(2 * solarMeanAnomaly.radians)) + 282.634
        return solarLongitudeApprox.truncatingRemainder(dividingBy: 360)
    }

    var rightAscension: Double {
        let x = 0.91764 * tan(longitude.radians)
        var solarRightAscensionApprox = atan(x).degrees
        let LQuadrant = (floor(longitude / 90.0)) * 90
        let RAQuadrant = (floor(solarRightAscensionApprox / 90.0)) * 90
        solarRightAscensionApprox =
            solarRightAscensionApprox + (LQuadrant - RAQuadrant)
        return solarRightAscensionApprox / SOLAR_DEGREES_PER_HOUR
    }

    var declination: (sin: Double, cos: Double) {
        let s = 0.39782 * sin(longitude.radians)
        let c = cos(asin(s))
        return (s, c)
    }

    func localHourAngleCosine(_ zenith: Zenith, latitude: Double) -> Double {
        let zenithCosine = cos(zenith.rawValue.radians)
        return (zenithCosine - (declination.sin * sin(latitude.radians)))
            / (declination.cos * cos(latitude.radians))
    }
}

extension Double {
    var radians: Double { self * Double.pi / 180 }
    var degrees: Double { self * 180 / Double.pi }
}

private enum Event {
    case sunrise
    case sunset
}

func longitudinalHour(_ longitude: CLLocationDegrees) -> Double {
    return longitude / SOLAR_DEGREES_PER_HOUR

}

extension Date {
    fileprivate func timeOfEvent(
        _ event: Event,
        location: CLLocation,
        zenith: Zenith
    ) -> Date? {
        var utcCal = Calendar.current
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let dayOfYear = Double(
            utcCal.ordinality(of: .day, in: .year, for: self) ?? 0
        )
        let sun = Sun(dayOfYear: dayOfYear)
        let guess = (event == .sunrise) ? 6.0 : 18.0
        let approxT =
            ((guess - longitudinalHour(location.coordinate.longitude)) / 24.0)
            + dayOfYear
        let cosHour = sun.localHourAngleCosine(
            zenith,
            latitude: location.coordinate.latitude
        )
        guard cosHour > -1 && cosHour < 1 else { return nil }
        let multiplier = (event == .sunrise) ? -1.0 : 1.0
        let hour = (acos(cosHour).degrees * multiplier) / 15
        let T = (hour + sun.rightAscension - (0.06571 * approxT) - 6.622)
        var UTC = (T - longitudinalHour(location.coordinate.longitude))
        if UTC < 0 { UTC += 24 } else if UTC > 24 { UTC -= 24 }
        var dateComponents = utcCal.dateComponents(
            [.day, .month, .year],
            from: self
        )
        dateComponents.hour = Int(UTC)
        dateComponents.minute = Int(
            (UTC * 60).truncatingRemainder(dividingBy: 60)
        )
        dateComponents.second = Int(
            (UTC * 3600).truncatingRemainder(dividingBy: 60)
        )
        return utcCal.date(from: dateComponents)
    }

    func sunrise(_ location: CLLocation, zenith: Zenith = .official) -> Date? {
        return timeOfEvent(.sunrise, location: location, zenith: zenith)
    }

    func sunset(_ location: CLLocation, zenith: Zenith = .official) -> Date? {
        return timeOfEvent(.sunset, location: location, zenith: zenith)
    }
}

// MARK: - Extensión para interpolación de colores
extension Color {
    func mix(with color: Color, amount: Double) -> Color {
        let fromC = UIColor(self)
        let toC = UIColor(color)
        var fr: CGFloat = 0
        var fg: CGFloat = 0
        var fb: CGFloat = 0
        var fa: CGFloat = 0
        fromC.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        var tr: CGFloat = 0
        var tg: CGFloat = 0
        var tb: CGFloat = 0
        var ta: CGFloat = 0
        toC.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        let r = fr + (tr - fr) * CGFloat(amount)
        let g = fg + (tg - fg) * CGFloat(amount)
        let b = fb + (tb - fb) * CGFloat(amount)
        let a = fa + (ta - fa) * CGFloat(amount)
        return Color(UIColor(red: r, green: g, blue: b, alpha: a))
    }
}

// MARK: - Main App
@main
struct EsDeNocheApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
        {
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
        {
            manager.requestLocation()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        location = locations.first
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("Error al obtener ubicación: \(error.localizedDescription)")
    }
}

// MARK: - Voice Manager
class VoiceManager {
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-ES")
        utterance.rate = 0.5  // Ajustado para mayor claridad
        utterance.pitchMultiplier = 1.0  // Tono natural
        synth.speak(utterance)
    }
}

// MARK: - Main View
struct ContentView: View {
    @State private var currentDate = Date()

    // Persistencia con @AppStorage
    @AppStorage("totalChecks") private var totalChecks = 0
    @AppStorage("checksToday") private var checksToday = 0
    @AppStorage("lastCheckDateString") private var lastCheckDateString = ""
    @AppStorage("nightChecks") private var nightChecks = 0
    @AppStorage("dayChecks") private var dayChecks = 0

    private let voiceManager = VoiceManager()
    @StateObject private var locationManager = LocationManager()

    var isNight: Bool {
        let now = Date()
        if let location = locationManager.location,
            let sunrise = now.sunrise(location),
            let sunset = now.sunset(location)
        {
            return now < sunrise || now > sunset
        } else {
            let hour = Calendar.current.component(.hour, from: now)
            return hour >= 20 || hour < 6
        }
    }

    private func dayProgress() -> Double {
        let now = Date()
        if let location = locationManager.location,
            let sunrise = now.sunrise(location),
            let sunset = now.sunset(location)
        {
            if now < sunrise || now > sunset {
                return -1
            }
            let dayLength = sunset.timeIntervalSince(sunrise)
            let timeSinceSunrise = now.timeIntervalSince(sunrise)
            return timeSinceSunrise / dayLength
        } else {
            let hour =
                Double(Calendar.current.component(.hour, from: now)) + Double(
                    Calendar.current.component(.minute, from: now)
                ) / 60.0
            if hour >= 6 && hour < 20 {
                return (hour - 6) / 14.0
            } else {
                return -1
            }
        }
    }

    private func interpolate(colors: [Double: Color], progress: Double) -> Color
    {
        let sortedKeys = colors.keys.sorted()
        if progress <= sortedKeys.first! {
            return colors[sortedKeys.first!]!
        }
        if progress >= sortedKeys.last! {
            return colors[sortedKeys.last!]!
        }
        for i in 0..<sortedKeys.count - 1 {
            let k1 = sortedKeys[i]
            let k2 = sortedKeys[i + 1]
            if progress >= k1 && progress <= k2 {
                let t = (progress - k1) / (k2 - k1)
                return colors[k1]!.mix(with: colors[k2]!, amount: t)
            }
        }
        return colors[sortedKeys.last!]!
    }

    var currentGradient: Gradient {
        let progress = dayProgress()
        if progress < 0 {
            // Noche: degradado de azul oscuro a negro
            return Gradient(colors: [
                Color(red: 0.0, green: 0.0, blue: 0.2), .black,
            ])
        } else {
            // Día: interpolación de colores
            let topColors: [Double: Color] = [
                0.0: .red,  // Amanecer
                0.5: .blue,  // Mediodía
                1.0: .orange,  // Atardecer
            ]
            let bottomColors: [Double: Color] = [
                0.0: .yellow,  // Amanecer
                0.5: .cyan,  // Mediodía
                1.0: .red,  // Atardecer
            ]
            let top = interpolate(colors: topColors, progress: progress)
            let bottom = interpolate(colors: bottomColors, progress: progress)
            return Gradient(colors: [top, bottom])
        }
    }

    var nightIcon: String {
        isNight ? "🌙" : "☀️"
    }

    var nightMessage: String {
        isNight
            ? "Sí, es de noche\nvete a dormir"
            : "No, aún hay luz\nquédate despierto"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: currentGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 40) {
                    Spacer()

                    Text(nightIcon)
                        .font(.system(size: 120))
                        .shadow(
                            color: isNight
                                ? .white.opacity(0.3) : .black.opacity(0.2),
                            radius: 20
                        )

                    Text("¿Es de noche aquí?")
                        .font(
                            .system(size: 32, weight: .bold, design: .rounded)
                        )
                        .foregroundColor(isNight ? .white : .black)
                        .multilineTextAlignment(.center)

                    Text(nightMessage)
                        .font(
                            .system(size: 24, weight: .medium, design: .rounded)
                        )
                        .foregroundColor(
                            isNight ? .white.opacity(0.8) : .black.opacity(0.8)
                        )
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    HStack(spacing: 20) {
                        VStack {
                            Text("\(totalChecks)")
                                .font(
                                    .system(
                                        size: 28,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .foregroundColor(isNight ? .white : .black)
                            Text("total")
                                .font(.caption)
                                .foregroundColor(
                                    isNight
                                        ? .white.opacity(0.6)
                                        : .black.opacity(0.6)
                                )
                        }

                        VStack {
                            Text("\(checksToday)")
                                .font(
                                    .system(
                                        size: 28,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .foregroundColor(isNight ? .white : .black)
                            Text("hoy")
                                .font(.caption)
                                .foregroundColor(
                                    isNight
                                        ? .white.opacity(0.6)
                                        : .black.opacity(0.6)
                                )
                        }

                        VStack {
                            Text("🌙 \(nightChecks)")
                                .font(
                                    .system(
                                        size: 20,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .foregroundColor(isNight ? .white : .black)
                            Text("☀️ \(dayChecks)")
                                .font(
                                    .system(
                                        size: 20,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .foregroundColor(isNight ? .white : .black)
                        }
                    }
                    .padding()
                    .background(
                        isNight
                            ? Color.white.opacity(0.1)
                            : Color.black.opacity(0.05)
                    )
                    .cornerRadius(15)

                    Spacer()

                    VStack(spacing: 15) {
                        Button {
                            voiceManager.speak(nightMessage)
                            recordCheck()
                        } label: {
                            HStack(spacing: 12) {
                                //                                Image(systemName: "play.fill")
                                Text("Comprueba")
                            }
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isNight ? .black : .white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 15)
                            .background(isNight ? Color.white : Color.black)
                            .cornerRadius(25)
                        }

                        Button {
                            totalChecks = 0
                            checksToday = 0
                            lastCheckDateString = ""
                            nightChecks = 0
                            dayChecks = 0
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.clockwise")
                                Text("Reiniciar Contador")
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isNight ? .white : .black)
                            .padding(.horizontal, 25)
                            .padding(.vertical, 12)
                            .background(
                                isNight
                                    ? Color.white.opacity(0.2)
                                    : Color.black.opacity(0.1)
                            )
                            .cornerRadius(20)
                        }
                    }
                    .padding(.bottom, 20)

                    VStack(spacing: 8) {
                        if locationManager.authorizationStatus
                            == .authorizedWhenInUse
                            || locationManager.authorizationStatus
                                == .authorizedAlways
                        {
                            Label(
                                "Usando tu ubicación",
                                systemImage: "location.fill"
                            )
                            .font(.caption)
                            .foregroundColor(
                                isNight
                                    ? .white.opacity(0.5) : .black.opacity(0.5)
                            )
                        } else {
                            Label(
                                "Usando hora local",
                                systemImage: "clock.fill"
                            )
                            .font(.caption)
                            .foregroundColor(
                                isNight
                                    ? .white.opacity(0.5) : .black.opacity(0.5)
                            )
                        }

                        Text(currentDate, style: .time)
                            .font(.largeTitle)  // Tamaño más grande
                            .foregroundColor(
                                isNight
                                    ? .white.opacity(0.3) : .black.opacity(0.3)
                            )

                        Text("Tu ubicación")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .padding(.bottom, 10)
                }
                .padding()
            }
            .onAppear {
                currentDate = Date()
                startTimer()
            }
            .preferredColorScheme(isNight ? .dark : .light)
        }
    }

    private func startTimer() {
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            currentDate = Date()
        }
    }

    private func recordCheck() {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        let todayString = formatter.string(from: now)

        if lastCheckDateString != todayString {
            checksToday = 0
            lastCheckDateString = todayString
        }

        totalChecks += 1
        checksToday += 1
        if isNight {
            nightChecks += 1
        } else {
            dayChecks += 1
        }
    }
}

// MARK: - Preview
// pruebas de ejemplo de uso conIA
#Preview {
    ContentView()
}
