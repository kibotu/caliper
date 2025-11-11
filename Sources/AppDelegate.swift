import UIKit
import Orchard

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Configure Orchard logger
        setupLogger()
        
        // Log a joke with style
        logJoke()
        
        // Setup window
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()
        
        return true
    }
    
    private func setupLogger() {
        Orchard.loggers.append(ConsoleLogger())
        
        Orchard.tag("Setup").icon("🌳").i("Orchard logger configured successfully")
    }
    
    private func logJoke() {
        let jokes = [
            "Why do programmers prefer dark mode? Because light attracts bugs! 🐛",
            "How many programmers does it take to change a light bulb? None, that's a hardware problem! 💡",
            "Why do Java developers wear glasses? Because they can't C#! 👓",
            "What's a programmer's favorite hangout place? Foo Bar! 🍺",
            "Why did the developer go broke? Because he used up all his cache! 💰"
        ]
        
        let randomJoke = jokes.randomElement() ?? "No joke found!"
        
        Orchard.tag("Comedy").icon("🎭").i(
            "Daily Joke",
            [
                "joke": randomJoke,
                "timestamp": Date().description,
                "source": "AppDelegate"
            ]
        )
        
        Orchard.tag("Comedy").icon("😂").d(randomJoke)
    }
}

