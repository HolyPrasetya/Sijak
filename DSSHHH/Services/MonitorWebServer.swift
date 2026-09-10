import Foundation
import Network

/// Server HTTP + Server-Sent-Events ringan, host-only, dijalankan dari device Monitor (Mac atau nanti iPhone).
/// Tujuannya: siapa pun di WiFi yang sama bisa buka `http://<ip-host>:8080` di browser apa saja
/// buat lihat skor/round/waktu live, TANPA perlu install app atau punya Mac.
///
/// Sengaja pakai Server-Sent Events (bukan WebSocket) karena cuma butuh satu arah (host -> browser),
/// jadi tidak perlu implementasi handshake WebSocket manual — SSE cukup 1 HTTP response yang dibiarkan terbuka.
/// Prototype ini read-only (belum ada kontrol operator dari web).
final class MonitorWebServer {
    private var listener: NWListener?
    private var sseConnections: [NWConnection] = []
    private let queue = DispatchQueue(label: "MonitorWebServer")
    private var lastStateJSON: Data?

    func start(port: UInt16 = 8080) {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params, on: nwPort) else { return }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                NSLog("MonitorWebServer: listener failed: \(error)")
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        sseConnections.forEach { $0.cancel() }
        sseConnections.removeAll()
    }

    /// Dipanggil host tiap kali ScoreState berubah — push ke semua browser yang lagi buka /events.
    func broadcast(scoreState: ScoreState) {
        guard let data = try? JSONEncoder().encode(scoreState) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.lastStateJSON = data
            let payload = self.ssePayload(from: data)
            for connection in self.sseConnections {
                connection.send(content: payload, completion: .contentProcessed { _ in })
            }
        }
    }

    private func ssePayload(from json: Data) -> Data {
        var text = "data: "
        text += String(data: json, encoding: .utf8) ?? "{}"
        text += "\n\n"
        return Data(text.utf8)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let firstLine = request.split(separator: "\r\n").first.map(String.init) ?? ""
            let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"

            if path == "/events" {
                self.sendSSEHeaders(on: connection)
                self.sseConnections.append(connection)
                if let last = self.lastStateJSON {
                    connection.send(content: self.ssePayload(from: last), completion: .contentProcessed { _ in })
                }
                connection.stateUpdateHandler = { [weak self, weak connection] state in
                    guard let self, let connection else { return }
                    switch state {
                    case .cancelled, .failed:
                        self.sseConnections.removeAll { $0 === connection }
                    default:
                        break
                    }
                }
            } else {
                self.sendHTMLPage(on: connection)
            }
        }
    }

    private func sendSSEHeaders(on connection: NWConnection) {
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
        connection.send(content: Data(headers.utf8), completion: .contentProcessed { _ in })
    }

    private func sendHTMLPage(on connection: NWConnection) {
        let body = Data(Self.displayHTML.utf8)
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(headers.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Halaman display read-only (embedded, tanpa file eksternal)

    private static let displayHTML = """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>DSSHHH Live Scoreboard</title>
    <style>
      :root { color-scheme: dark; }
      * { box-sizing: border-box; margin:0; padding:0; }
      body { background:#0f0f0f; color:#fff; font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display',sans-serif; height:100vh; display:flex; flex-direction:column; overflow:hidden; }
      header { background:#151515; padding:16px 28px; display:flex; align-items:center; justify-content:space-between; }
      .score { display:flex; align-items:center; gap:10px; }
      .score .value { font-size:46px; font-weight:800; }
      .red .value { color:#ff3b30; }
      .blue .value { color:#2f80ff; }
      .title { font-size:18px; font-weight:700; letter-spacing:1px; }
      .center { text-align:center; }
      .center .timer { font-size:56px; font-weight:800; font-variant-numeric: tabular-nums; }
      .center .round { margin-top:4px; font-size:14px; color:#999; font-weight:600; }
      .pips { display:flex; gap:8px; justify-content:center; margin-top:6px; }
      .pip { width:12px; height:12px; border-radius:50%; background:#444; }
      .pip.red { background:#ff3b30; }
      .pip.blue { background:#2f80ff; }
      main { flex:1; display:flex; }
      .panel { flex:1; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:14px; }
      .panel.red { background:linear-gradient(135deg,#d81919,#9b0d0d); }
      .panel.blue { background:linear-gradient(135deg,#1667ff,#10368b); }
      .panel .label { font-size:20px; font-weight:700; }
      .panel .value { font-size:clamp(60px,14vw,160px); font-weight:800; }
      .panel .gamjeom { font-size:14px; opacity:.85; }
      .overlay { position:fixed; inset:0; background:rgba(0,0,0,.75); display:none; align-items:center; justify-content:center; flex-direction:column; gap:16px; text-align:center; padding:20px; }
      .overlay.show { display:flex; }
      .overlay h1 { font-size:34px; }
      .winner.red { color:#ff3b30; }
      .winner.blue { color:#2f80ff; }
      .conn { position:fixed; top:8px; right:12px; font-size:11px; color:#666; }
    </style>
    </head>
    <body>
      <div class="conn" id="conn">connecting…</div>
      <header>
        <div class="score red"><div class="value" id="redScore">0</div><div class="title">RED</div></div>
        <div class="center">
          <div class="timer" id="timer">00:00</div>
          <div class="round" id="roundLabel">ROUND 1 / 3</div>
          <div class="pips" id="pips"></div>
        </div>
        <div class="score blue"><div class="value" id="blueScore">0</div><div class="title">BLUE</div></div>
      </header>
      <main>
        <div class="panel red"><div class="label">RED</div><div class="value" id="redBig">0</div><div class="gamjeom" id="redGamjeom">Gam-jeom: 0</div></div>
        <div class="panel blue"><div class="label">BLUE</div><div class="value" id="blueBig">0</div><div class="gamjeom" id="blueGamjeom">Gam-jeom: 0</div></div>
      </main>
      <div class="overlay" id="overlay">
        <h1 id="overlayTitle"></h1>
        <div id="overlaySubtitle" style="font-size:24px;font-weight:700;"></div>
      </div>
    <script>
    function fmt(s) { s = Math.max(0, Math.round(s)); const m = Math.floor(s/60), r = s%60; return String(m).padStart(2,'0')+':'+String(r).padStart(2,'0'); }
    function render(state) {
      document.getElementById('redScore').textContent = state.redScore;
      document.getElementById('blueScore').textContent = state.blueScore;
      document.getElementById('redBig').textContent = state.redScore;
      document.getElementById('blueBig').textContent = state.blueScore;
      document.getElementById('redGamjeom').textContent = 'Gam-jeom: ' + state.redPenalties;
      document.getElementById('blueGamjeom').textContent = 'Gam-jeom: ' + state.bluePenalties;
      document.getElementById('timer').textContent = fmt(state.timeRemaining);
      document.getElementById('roundLabel').textContent = 'ROUND ' + state.round + ' / 3';

      const pips = document.getElementById('pips');
      pips.innerHTML = '';
      for (let i=0;i<3;i++){
        const el = document.createElement('div');
        const w = (state.roundHistory || [])[i];
        el.className = 'pip' + (w ? (' '+w) : '');
        pips.appendChild(el);
      }

      const overlay = document.getElementById('overlay');
      const title = document.getElementById('overlayTitle');
      const sub = document.getElementById('overlaySubtitle');
      if (state.phase === 'roundEnded') {
        overlay.classList.add('show');
        title.textContent = 'ROUND ' + state.round + ' COMPLETE';
        sub.textContent = state.roundWinner ? (state.roundWinner.toUpperCase() + ' WINS THE ROUND') : 'SCORE TIED';
        sub.className = 'winner ' + (state.roundWinner || '');
      } else if (state.phase === 'matchOver') {
        overlay.classList.add('show');
        title.textContent = 'MATCH COMPLETE';
        sub.textContent = state.matchWinner ? (state.matchWinner.toUpperCase() + ' WINS THE MATCH') : '';
        sub.className = 'winner ' + (state.matchWinner || '');
      } else {
        overlay.classList.remove('show');
      }
    }

    function connect() {
      const es = new EventSource('/events');
      es.onopen = () => { document.getElementById('conn').textContent = 'live'; };
      es.onmessage = (e) => { try { render(JSON.parse(e.data)); } catch(err) {} };
      es.onerror = () => { document.getElementById('conn').textContent = 'reconnecting…'; };
    }
    connect();
    </script>
    </body>
    </html>
    """
}

/// Alamat IP WiFi lokal device ini (interface en0/en1) — dipakai buat kasih tahu operator
/// URL apa yang harus dibuka di browser laptop/device lain di jaringan yang sama.
func localWiFiIPAddress() -> String? {
    var address: String?
    var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
    defer { freeifaddrs(ifaddrPtr) }

    var ptr = firstAddr
    while true {
        let interface = ptr.pointee
        if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
            let name = String(cString: interface.ifa_name)
            if name == "en0" || name == "en1" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                address = String(cString: hostname)
                break
            }
        }
        guard let next = interface.ifa_next else { break }
        ptr = next
    }
    return address
}
