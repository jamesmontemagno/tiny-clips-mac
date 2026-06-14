using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Graphics.Imaging;
using Windows.Media.Core;
using Windows.Media.MediaProperties;
using Windows.Media.Transcoding;
using Windows.Storage;
using Windows.Storage.Streams;

namespace MediaFoundationEncoderSpike;

class Program
{
    const int WIDTH = 1280;
    const int HEIGHT = 720;
    const int FPS = 30;
    const int FRAME_COUNT = 90; // 3 seconds
    const uint VIDEO_BIT_RATE = 8_000_000; // 8 Mbps
    
    static string outputPath = "output.mp4";
    
    [STAThread]
    static async Task Main(string[] args)
    {
        Console.WriteLine("=== Media Foundation H.264/MP4 Encoder Spike (WinRT) ===\n");
        
        try
        {
            Console.WriteLine("Using Windows.Media APIs for encoding...");
            await EncodeVideo();
            
            // Validate the output
            ValidateOutput();
            
            Console.WriteLine("\n=== SPIKE COMPLETE ===");
            Console.WriteLine($"Output file: {Path.GetFullPath(outputPath)}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"\n✗ FATAL ERROR: {ex.Message}");
            Console.WriteLine(ex.StackTrace);
            Environment.Exit(1);
        }
    }

    static async Task EncodeVideo()
    {
        Console.WriteLine("Creating video file...");
        
        // Create output file
        var folder = await StorageFolder.GetFolderFromPathAsync(Environment.CurrentDirectory);
        var file = await folder.CreateFileAsync("output.mp4", CreationCollisionOption.ReplaceExisting);
        
        // Create encoding profile
        var profile = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.HD720p);
        profile.Video.Bitrate = VIDEO_BIT_RATE;
        profile.Video.FrameRate.Numerator = FPS;
        profile.Video.FrameRate.Denominator = 1;
        profile.Video.Width = WIDTH;
        profile.Video.Height = HEIGHT;
        profile.Video.PixelAspectRatio.Numerator = 1;
        profile.Video.PixelAspectRatio.Denominator = 1;
        
        // Configure AAC audio
        profile.Audio = AudioEncodingProperties.CreateAac(48000, 2, 192000);
        
        Console.WriteLine($"Profile: H.264 {WIDTH}x{HEIGHT} @ {FPS}fps, AAC 48kHz stereo");
        
        // Create MediaStreamSource for custom frame generation
        var videoProps = VideoEncodingProperties.CreateUncompressed(MediaEncodingSubtypes.Bgra8, WIDTH, HEIGHT);
        videoProps.FrameRate.Numerator = (uint)FPS;
        videoProps.FrameRate.Denominator = 1;
        
        var videoDescriptor = new VideoStreamDescriptor(videoProps);
        
        var audioProps = AudioEncodingProperties.CreatePcm(48000, 2, 16);
        var audioDescriptor = new AudioStreamDescriptor(audioProps);
        
        var mediaStreamSource = new MediaStreamSource(videoDescriptor, audioDescriptor);
        mediaStreamSource.BufferTime = TimeSpan.Zero;
        
        int currentFrame = 0;
        long videoTimestamp = 0;
        long audioTimestamp = 0;
        var frameDuration = TimeSpan.FromSeconds(1.0 / FPS);
        
        mediaStreamSource.SampleRequested += (sender, args) =>
        {
            var deferral = args.Request.GetDeferral();
            
            try
            {
                if (args.Request.StreamDescriptor == videoDescriptor && currentFrame < FRAME_COUNT)
                {
                    // Generate video frame
                    var frameBytes = GenerateAnimatedFrame(currentFrame);
                    var buffer = frameBytes.AsBuffer();
                    
                    var sample = MediaStreamSample.CreateFromBuffer(buffer, TimeSpan.FromTicks(videoTimestamp));
                    sample.Duration = frameDuration;
                    
                    args.Request.Sample = sample;
                    
                    videoTimestamp += frameDuration.Ticks;
                    currentFrame++;
                    
                    if (currentFrame % 30 == 0)
                        Console.WriteLine($"  Encoded {currentFrame}/{FRAME_COUNT} frames...");
                }
                else if (args.Request.StreamDescriptor == audioDescriptor && audioTimestamp < videoTimestamp + frameDuration.Ticks)
                {
                    // Generate silent audio
                    int samplesPerFrame = 48000 / FPS;
                    var silenceBytes = new byte[samplesPerFrame * 2 * 2]; // 16-bit stereo
                    var buffer = silenceBytes.AsBuffer();
                    
                    var sample = MediaStreamSample.CreateFromBuffer(buffer, TimeSpan.FromTicks(audioTimestamp));
                    sample.Duration = frameDuration;
                    
                    args.Request.Sample = sample;
                    audioTimestamp += frameDuration.Ticks;
                }
            }
            finally
            {
                deferral.Complete();
            }
        };
        
        mediaStreamSource.Starting += (sender, args) =>
        {
            args.Request.SetActualStartPosition(TimeSpan.Zero);
        };
        
        // Transcode
        Console.WriteLine("\nEncoding video...");
        var transcoder = new MediaTranscoder();
        transcoder.HardwareAccelerationEnabled = true;
        
        var prepareResult = await transcoder.PrepareMediaStreamSourceTranscodeAsync(mediaStreamSource, await file.OpenAsync(FileAccessMode.ReadWrite), profile);
        
        if (prepareResult.CanTranscode)
        {
            Console.WriteLine($"Hardware acceleration: {transcoder.HardwareAccelerationEnabled}");
            await prepareResult.TranscodeAsync();
            Console.WriteLine("✓ Encoding complete");
        }
        else
        {
            throw new Exception($"Cannot transcode: {prepareResult.FailureReason}");
        }
    }

    static byte[] GenerateAnimatedFrame(int frameIndex)
    {
        // Generate BGRA frame with animated content
        byte[] frame = new byte[WIDTH * HEIGHT * 4];
        
        // Moving rectangle
        int rectWidth = 200;
        int rectHeight = 100;
        int rectX = (frameIndex * 10) % (WIDTH - rectWidth);
        int rectY = HEIGHT / 2 - rectHeight / 2;
        
        // Animated background
        byte bgR = (byte)((frameIndex * 2) % 256);
        byte bgG = (byte)((frameIndex * 3) % 256);
        byte bgB = (byte)((frameIndex * 5) % 256);
        
        for (int y = 0; y < HEIGHT; y++)
        {
            for (int x = 0; x < WIDTH; x++)
            {
                int offset = (y * WIDTH + x) * 4;
                bool inRect = x >= rectX && x < rectX + rectWidth && y >= rectY && y < rectY + rectHeight;
                
                if (inRect)
                {
                    frame[offset + 0] = 0;      // B
                    frame[offset + 1] = 200;    // G
                    frame[offset + 2] = 255;    // R
                    frame[offset + 3] = 255;    // A
                }
                else
                {
                    frame[offset + 0] = bgB;
                    frame[offset + 1] = bgG;
                    frame[offset + 2] = bgR;
                    frame[offset + 3] = 255;
                }
            }
        }
        
        return frame;
    }

    static void ValidateOutput()
    {
        Console.WriteLine("\n=== VALIDATION ===");
        
        if (!File.Exists(outputPath))
        {
            Console.WriteLine("✗ Output file not found!");
            return;
        }
        
        FileInfo fileInfo = new FileInfo(outputPath);
        Console.WriteLine($"File size: {fileInfo.Length:N0} bytes ({fileInfo.Length / 1024.0:F2} KB)");
        
        if (fileInfo.Length > 100000)
        {
            Console.WriteLine("✓ File has reasonable size for video content");
            Console.WriteLine("✓ MP4 file created successfully");
            Console.WriteLine("\nTo verify playback, open the file in Windows Media Player or another video player.");
        }
        else
        {
            Console.WriteLine("⚠ File size seems small - encoding may not have completed properly");
        }
    }
}
