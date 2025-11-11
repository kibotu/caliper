import UIKit
import Orchard

class ViewController: UIViewController {
    
    private let jokeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .systemBlue
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let refreshButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Get Another Joke 🎭", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        Orchard.tag("UI").icon("📱").d("ViewController loaded")
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(jokeLabel)
        view.addSubview(refreshButton)
        
        NSLayoutConstraint.activate([
            jokeLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            jokeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            jokeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            refreshButton.topAnchor.constraint(equalTo: jokeLabel.bottomAnchor, constant: 40),
            refreshButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        refreshButton.addTarget(self, action: #selector(refreshJoke), for: .touchUpInside)
        
        refreshJoke()
    }
    
    @objc private func refreshJoke() {
        let jokes = [
            "Why do programmers prefer dark mode? Because light attracts bugs! 🐛",
            "How many programmers does it take to change a light bulb? None, that's a hardware problem! 💡",
            "Why do Java developers wear glasses? Because they can't C#! 👓",
            "What's a programmer's favorite hangout place? Foo Bar! 🍺",
            "Why did the developer go broke? Because he used up all his cache! 💰",
            "What do you call a programmer from Finland? Nerdic! 🇫🇮",
            "Why don't programmers like nature? It has too many bugs! 🌲",
            "What's a programmer's favorite snack? Microchips! 🍟"
        ]
        
        let joke = jokes.randomElement() ?? "No joke found!"
        jokeLabel.text = joke
        
        Orchard.tag("Comedy").icon("🎭").i("New joke displayed", ["joke": joke])
    }
}

