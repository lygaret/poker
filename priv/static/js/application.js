(() => {
    const roomId = document.body.dataset.roomId;
    window.socket = new WebSocket(`ws://localhost:4000/ws/${roomId}`);

    let room = null;
    socket.addEventListener("message", (e) => {
        const data = JSON.parse(e.data);
        if (data.room) {
            room = data.room;
            console.log("room", room)
        }
        else if (data.patch) {
            room = jsonpatch.apply(room, data.patch);
            console.log("patch", room)
        }
        else if (data.error) {
            console.log("error", data.error)
        }
    });

    const createHeartbeat = function(socket, timeout) {
        let timer;
        const heartbeat = () => {
            socket.send('ok');
            timer = setTimeout(heartbeat, timeout, socket, timeout);
        };

        heartbeat();
        return () => {
            clearTimeout(timer);
        };
    }

    socket.addEventListener("open", (e) => {
        console.log("open", e);

        const cancel = createHeartbeat(socket, 30000);
        socket.addEventListener("close", (e) => {
            cancel();
        });
    });
})()
