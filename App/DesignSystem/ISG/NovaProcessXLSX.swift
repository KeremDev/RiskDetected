import Foundation

/// Minimal OOXML workbook using inline text cells, so user text never becomes a formula.
enum NovaProcessXLSX {
    static func write(_ row:NovaProcessRow,kind:NovaProcessKind,owner:UUID) throws -> URL {
        func display(_ v:NovaModuleValue)->String {
            switch v {case .array(let a):return a.map(display).joined(separator:"\n")
            case .object(let o):return o["name"]?.text ?? o.values.map(display).joined(separator:" · ")
            case .number(let n):return n.rounded()==n ? String(Int(n)):String(n)
            default:return v.text}
        }
        var rows = [["Belge",row.number ?? row.id.uuidString],["Firma",row.company_name],["Modül",kind.title]]
        func append(_ entry:NovaProcessRow,_ spec:NovaProcessKind) {
            for field in spec.fields {
                let val=entry.values[field.id] ?? .null
                rows.append([field.title,field.id == "workplace_id" ? (entry.workplace_name ?? ""):(field.choices[val.text] ?? display(val))])
            }
        }
        append(row,kind)
        for child in row.children ?? [] {rows.append(["",""]);append(child,.get(row.child_kind ?? kind.code))}
        func xml(_ s:String)->String {
            s.unicodeScalars.filter{$0.value==9 || $0.value==10 || $0.value==13 || $0.value>=32}.map(String.init).joined()
                .replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;")
        }
        let sheetRows=rows.enumerated().map { i,cells in
            "<row r=\"\(i+1)\">"+cells.enumerated().map { j,value in "<c r=\"\(j==0 ? "A":"B")\(i+1)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xml(value))</t></is></c>" }.joined()+"</row>"
        }.joined()
        let entries:[(String,String)] = [
            ("[Content_Types].xml","<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>"),
            ("_rels/.rels","<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"),
            ("xl/workbook.xml","<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Kayıt\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"),
            ("xl/_rels/workbook.xml.rels","<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>"),
            ("xl/worksheets/sheet1.xml","<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><cols><col min=\"1\" max=\"1\" width=\"32\" customWidth=\"1\"/><col min=\"2\" max=\"2\" width=\"85\" customWidth=\"1\"/></cols><sheetData>\(sheetRows)</sheetData></worksheet>")]
        var zip=Data();var central=Data()
        func u16(_ n:Int)->Data {var n=UInt16(n).littleEndian;return withUnsafeBytes(of:&n){Data($0)}}
        func u32(_ n:UInt32)->Data {var n=n.littleEndian;return withUnsafeBytes(of:&n){Data($0)}}
        for (name,text) in entries {
            let n=Data(name.utf8),d=Data(text.utf8),offset=UInt32(zip.count)
            var crc:UInt32=0xffffffff
            for byte in d {crc ^= UInt32(byte);for _ in 0..<8 {crc = (crc >> 1) ^ ((crc & 1)==1 ? 0xedb88320:0)}}
            crc ^= 0xffffffff
            for chunk in [u32(0x04034b50),u16(20),u16(0),u16(0),u16(0),u16(33),u32(crc),u32(UInt32(d.count)),u32(UInt32(d.count)),u16(n.count),u16(0),n,d] { zip.append(chunk) }
            for chunk in [u32(0x02014b50),u16(20),u16(20),u16(0),u16(0),u16(0),u16(33),u32(crc),u32(UInt32(d.count)),u32(UInt32(d.count)),u16(n.count),u16(0),u16(0),u16(0),u16(0),u32(0),u32(offset),n] { central.append(chunk) }
        }
        let start=UInt32(zip.count);zip+=central
        for chunk in [u32(0x06054b50),u16(0),u16(0),u16(entries.count),u16(entries.count),u32(UInt32(central.count)),u32(start),u16(0)] { zip.append(chunk) }
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("process-\(owner)")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let url=folder.appendingPathComponent("\(kind.code)-\(row.id)-\(row.expected.prefix(8)).xlsx")
        try zip.write(to:url,options:.atomic);return url
    }
}
