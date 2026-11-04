// swift-tools-version:5.9
import PackageDescription
let package = Package(name:"Vigil", platforms:[.macOS(.v14)], products:[.library(name:"VigilCore",targets:["VigilCore"])],targets:[
 .target(name:"VigilCore",path:".",exclude:["App","Mac","iOS","Tests","docs","scripts","Resources","Shared/Fonts","GooglyEyes.xcodeproj"],sources:["Shared/FocusSession.swift","Core/VigilCore.swift","Core/OpenRouter.swift","Core/ModelHealthRouter.swift"]),
 .target(name:"VigilTransport",path:"Shared",exclude:["FocusSession.swift","Palette.swift","VoiceTurnBuffer.swift","Fonts"],sources:["GooglyLink.swift","SecurePairing.swift"]),
 .testTarget(name:"VigilTransportTests",dependencies:["VigilTransport"],path:"Tests/VigilTransportTests"),
 .testTarget(name:"VigilTests",dependencies:["VigilCore"],path:"Tests/VigilTests")
])
