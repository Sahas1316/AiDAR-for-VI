//
//  ViewController.swift
//  test
//
//  Created by Sahas Gurung on 2023/11/27.
//

import UIKit
import ARKit
import SceneKit
import AVFoundation
import Vision

class ViewController: UIViewController, ARSCNViewDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVAudioPlayerDelegate {
    var arView: ARSCNView!
    var speechSynthesizer: AVSpeechSynthesizer!
    var audioPlayer: AVAudioPlayer?
    var isAlarmPlaying = false
    var previousDistance: Float = 0.0
    var isMuted = false
    var isDistanceMuted = true
    var swipeGestureUp: UISwipeGestureRecognizer!
    var swipeGestureDown: UISwipeGestureRecognizer!
    var gptContent: String?
    var base64String: String?
    var isSwipedUp: Bool?
    var dataTask: URLSessionDataTask?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        arView = ARSCNView(frame: view.bounds)
        
        view.addSubview(arView)
        let scene = SCNScene()
        arView.scene = scene
        
        let configuration = ARWorldTrackingConfiguration()
        if #available(iOS 15.0, *) {
            configuration.sceneReconstruction = .meshWithClassification
        } else {
            configuration.environmentTexturing = .automatic
        }
        arView.session.run(configuration)
        
        speechSynthesizer = AVSpeechSynthesizer()
        
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.measureDistance()
        }
        timer.tolerance = 0.1
        RunLoop.current.add(timer, forMode: .common)
        
        // Add tap gesture recognizer
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGestureRecognizer.numberOfTapsRequired = 1
        arView.addGestureRecognizer(tapGestureRecognizer)

        // Add double tap gesture recognizer
        let doubleTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTapGestureRecognizer.numberOfTapsRequired = 2
        tapGestureRecognizer.require(toFail: doubleTapGestureRecognizer)
        arView.addGestureRecognizer(doubleTapGestureRecognizer)

        // Add swipe-up gesture recognizer
        swipeGestureUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp(_:)))
        swipeGestureUp.direction = .up
        arView.addGestureRecognizer(swipeGestureUp)
        
         // Add swipe-down gesture recognizer
         swipeGestureDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown(_:)))
         swipeGestureDown.direction = .down
         arView.addGestureRecognizer(swipeGestureDown)
        
        // Prevent the device from sleeping while the app is running
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Speak the distance once on app launch
        measureDistance()
    }
    
    // Handle single tap gesture
    @objc func handleTap(sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            isMuted = false
            // Speak the current distance
            isDistanceMuted = false
            measureDistance()
            isDistanceMuted = true
        }
    }
    
    // Handle double tap gesture
    @objc func handleDoubleTap(sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            // Toggle mute state
            isMuted = true
            // Stop the current alert when muting
            if isMuted {
                stopEmergencyBeepSound()
            }
            
            // Stop speech if it is currently speaking
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
            }
        }
    }
    
    //Swipe-up gesture handler
    @objc func handleSwipeUp(_ sender: UISwipeGestureRecognizer) {
        if sender.state == .ended {
            isSwipedUp = true
            // Stop speech if it is currently speaking
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
            }
            
            if let soundURL = Bundle.main.url(forResource: "swipe", withExtension: "mp3") {
                do {
                    audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                    audioPlayer?.enableRate = true
                    audioPlayer?.prepareToPlay()
                    audioPlayer?.play()
                } catch {
                    print("Error loading audio file: \(error)")
                }
            }
            // Cancel the GPT request
            cancelGPTRequest()
            
            takeSnapshot()
        }
    }
    
    //Swipe-down gesture handler
    @objc func handleSwipeDown(_ sender: UISwipeGestureRecognizer) {
        if sender.state == .ended {
            isSwipedUp = false
            // Stop speech if it is currently speaking
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
            }
            
            if let soundURL = Bundle.main.url(forResource: "swipe", withExtension: "mp3") {
                do {
                    audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                    audioPlayer?.enableRate = true
                    audioPlayer?.prepareToPlay()
                    audioPlayer?.play()
                } catch {
                    print("Error loading audio file: \(error)")
                }
            }
            // Cancel the GPT request
            cancelGPTRequest()
            
            takeSnapshot()
        }
    }
    
    //Take snapshot and sent it to GPT
    func takeSnapshot() {
        let snapshot = arView.snapshot()
        if let imageData = snapshot.jpegData(compressionQuality: 1.0) {
            base64String = imageData.base64EncodedString(options: .lineLength64Characters)
            sendImageToChatGPT(base64String: base64String!) { _ in}
        } else {
            print("Failed to convert UIImage to Base64")
        }
        
        let speechUtterance = AVSpeechUtterance(string: "画像認識中です。少々お待ち下さい。")
        speechUtterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        speechUtterance.rate = 0.6
        speechSynthesizer.speak(speechUtterance)
    }
    
    //Access GPT API for description
    func sendImageToChatGPT(base64String: String, completion: @escaping (String?) -> Void) {
        let apiKey = "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"
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Set the request body with parameters
        var parameters: [String: Any]?
        if (isSwipedUp!) {
            parameters = [
                "model": "gpt-4-vision-preview",
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "text",
                                "text": "視覚障害者のためにこの写真を50文字で説明してください。"
                            ],
                            [
                                "type": "image_url",
                                "image_url": [
                                    "url": "data:image/jpeg;base64,\(base64String)"
                                ]
                            ]
                        ]
                    ]
                ],
                "max_tokens": 300
            ]
        } else {
            parameters = [
                "model": "gpt-4-vision-preview",
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "text",
                                "text": "視覚障害者のためにこの写真を詳しく説明してください。"
                            ],
                            [
                                "type": "image_url",
                                "image_url": [
                                    "url": "data:image/jpeg;base64,\(base64String)"
                                ]
                            ]
                        ]
                    ]
                ],
                "max_tokens": 1000
            ]
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: parameters as Any, options: [])
        // Set the content type
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Create a URLSessionDataTask
        dataTask = URLSession.shared.dataTask(with: request) { [self] (data, response, error) in
            // Check if there is an error and handle it
            if let error = error {
                print("Error: \(error)")
                completion(nil)
                return
            }

            // Check if the task was canceled
            if (error as NSError?)?.code == NSURLErrorCancelled {
                print("GPT request canceled.")
                completion(nil)
                return
            }

            // Handle the response data
            guard let data = data else {
                print("No data received")
                completion(nil)
                return
            }

            // Parse the response data
            do {
                let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                
                // Extract and print the content of the message
                if let choices = jsonResponse?["choices"] as? [[String: Any]],
                   let messageContent = choices.first?["message"] as? [String: Any],
                   let content = messageContent["content"] as? String {
                    print("Message Content: \(content)")
                    
                    // Store the GPT content
                    self.gptContent = content
                    
                    // Call the completion handler with the GPT content
                    completion(content)
                    
                    // Directly speak the content after receiving the response
                    self.speakContent(content: content)
                } else {
                    print("No message content found in the response.")
                    completion(nil)
                }
            } catch {
                print("Error parsing response: \(error)")
                completion(nil)
            }
        }
        
        // Resume the task to execute the request
        dataTask?.resume()
    }
    
    //Cancel the GPT request
    func cancelGPTRequest() {
        dataTask?.cancel()
    }
    
    //Speak the response fron the GPT
    func speakContent(content: String) {
        let speechUtterance = AVSpeechUtterance(string: content)
        speechUtterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        speechUtterance.rate = 0.6
        speechSynthesizer.speak(speechUtterance)
    }
    
    //Measure the distance
    func measureDistance() {
        if let currentFrame = arView.session.currentFrame {
            // Get the camera's transform
            let cameraTransform = currentFrame.camera.transform
            // Extract the translation part from the camera transform
            let translation = simd_make_float3(cameraTransform.columns.3)
            // Calculate the direction vector from the camera transform
            let direction = simd_make_float3(-cameraTransform.columns.2)
            // Define a query for the ARRaycast
            let query = ARRaycastQuery(
                origin: translation,
                direction: direction,
                allowing: .estimatedPlane,
                alignment: .any
            )
            
            // Perform the ARRaycast
            let results = arView.session.raycast(query)
            if let result = results.first {
                // Calculate the distance between camera and hit point
                let hitTranslation = simd_make_float3(result.worldTransform.columns.3)
                let distance = simd_distance(translation, hitTranslation)
                print("Distance: \(distance)")
                // Speak the distance and play the emergency beep sound
                if !isDistanceMuted {
                    speakDistance(distance: distance)
                }
                handleEmergencyBeepSound(distance: distance)
                //Thread.sleep(forTimeInterval: 1)
            } else {
                // Handle the case where no valid distance measurement is available
                print("No valid distance measurement available.")
                stopEmergencyBeepSound()
            }
        }
    }
    
    //Play the beep sound
    func handleEmergencyBeepSound(distance: Float) {
        guard !isMuted else {
            return // If muted, do not play the sound
        }
        
        // Determine which audio file to use based on the specified distance criteria
        var audioFileName: String
        if distance < 5.0 && distance >= 3.0 {
            audioFileName = "emergencyBeepSound1"
        } else if distance < 3.0 && distance >= 1.0 {
            audioFileName = "emergencyBeepSound2"
        } else if distance < 1.0 {
            audioFileName = "emergencyBeepSound3"
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        } else {
            stopEmergencyBeepSound()
            return // No valid audio file for the current distance
        }
        
        // Load and play the selected audio file
        if let soundURL = Bundle.main.url(forResource: audioFileName, withExtension: "mp3") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                audioPlayer?.enableRate = true
                audioPlayer?.volume = 0.7
//                audioPlayer?.delegate = self
                audioPlayer?.numberOfLoops = -1 // Set to -1 for infinite looping
                audioPlayer?.prepareToPlay()
//                audioPlayer?.rate = 1.0
                audioPlayer?.play()
                isAlarmPlaying = true
            } catch {
                print("Error loading audio file: \(error)")
            }
        }
    }
    
    //Stop the Beep sound
    func stopEmergencyBeepSound() {
        if let audioPlayer = audioPlayer {
            if audioPlayer.isPlaying {
                audioPlayer.stop()
                isAlarmPlaying = false
            }
        }
    }
    
    //Speak the distance
    func speakDistance(distance: Float) {
        let roundedDistance = String(format: "%.2f", distance)
        let speechUtterance = AVSpeechUtterance(string: "\(roundedDistance) メートルです。")
        // Set the language to Japanese
        speechUtterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        speechUtterance.rate = 0.6
        speechUtterance.volume = 1
        speechSynthesizer.speak(speechUtterance)
    }
    
    //Re-enable the idle timer when the view controller is deinitialized
    deinit {
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
