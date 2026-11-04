// swift-tools-version:5.9
import PackageDescription
let package = Package(name:"Vigil", platforms:[.macOS(.v14)], products:[.library(name:"VigilCore",targets:["VigilCore"])],targets:[
 .target(name:"VigilCore",path:".",exclude:["App","Mac","iOS","Tests","docs","scripts","Resources","Shared/Fonts","GooglyEyes.xcodeproj"],sources:["Shared/FocusSession.swift","Core/VigilCore.swift","Core/OpenRouter.swift"]),
 .testTarget(name:"VigilTests",dependencies:["VigilCore"],path:"Tests/VigilTests")
])
