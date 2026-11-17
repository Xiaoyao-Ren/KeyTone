import Cocoa
let destination=CommandLine.arguments[1]
let folder=URL(fileURLWithPath:destination)
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
 let image=NSImage(size:NSSize(width:size,height:size));image.lockFocus()
 let scale=CGFloat(size)/1024
 let transform=NSAffineTransform();transform.scale(by:scale);transform.concat()
 NSColor(calibratedRed:0.09,green:0.12,blue:0.13,alpha:1).setFill()
 NSBezierPath(roundedRect:NSRect(x:20,y:20,width:984,height:984),xRadius:220,yRadius:220).fill()
 for i in 0..<4 {
  let x=CGFloat(160+i*178),h:CGFloat=[390,520,460,350][i]
  NSColor(calibratedRed:0.26,green:0.74,blue:0.59,alpha:1).setFill()
  NSBezierPath(roundedRect:NSRect(x:x,y:(1024-h)/2,width:140,height:h),xRadius:35,yRadius:35).fill()
  NSColor.white.withAlphaComponent(0.2).setFill()
  NSBezierPath(roundedRect:NSRect(x:x+18,y:(1024-h)/2+h-55,width:104,height:13),xRadius:6,yRadius:6).fill()
 }
 image.unlockFocus()
 let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
 let png=bitmap.representation(using:.png,properties:[:])!
 if size<=512 {try png.write(to:folder.appendingPathComponent("icon_\(size)x\(size).png"))}
 if size>=32 {try png.write(to:folder.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png"))}
}
