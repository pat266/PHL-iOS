import SwiftUI

struct Home: View {
    
    @EnvironmentObject var recorder: Recorder
    
    var body: some View {
        TabView {
            
            RecorderView().tabItem {
                Image(systemName: "waveform")
                Text("Record")
            }
            
            AngleView().tabItem {
                Image(systemName: "iphone.gen1.radiowaves.left.and.right")
                Text("Angle")
            }
            
            SampleListView().tabItem {
                Image(systemName: "list.bullet")
                Text("Samples")
            }
            
        }.accentColor(recorder.isRecording ? .red : .blue)
    }
}

struct Home_Previews: PreviewProvider {
    static var previews: some View {
        Home().environmentObject(Recorder())
    }
}
