/**
 * JS Thin Bridge - Regular Script Version
 * Ensures globalThis.mbt_bridge is available immediately.
 */
(function() {
  const nodes = new Map()

  const bridge = {
    create: (id, tag) => {
      const el = tag === "" ? document.createTextNode("") : document.createElement(tag)
      nodes.set(id, el)
    },
    text: (id, text) => {
      const node = nodes.get(id)
      if (node) node.textContent = text
    },
    attr: (id, k, v) => {
      const node = nodes.get(id)
      if (node && node.setAttribute) node.setAttribute(k, v)
    },
    append: (pid, cid) => {
      const parent = pid === 0 ? document.body : nodes.get(pid)
      const child = nodes.get(cid)
      if (parent && child) parent.appendChild(child)
    },
    updateText: (id, text) => {
      const node = nodes.get(id)
      if (node) node.textContent = text
    },
    updateAttr: (id, k, v) => {
      const node = nodes.get(id)
      if (node && node.setAttribute) node.setAttribute(k, v)
    },
    remove: (id) => {
      const node = nodes.get(id)
      if (node && node.parentNode) node.parentNode.removeChild(node)
      nodes.delete(id)
    },
    listen: (id, event, cb_id) => {
      const node = nodes.get(id)
      if (node) {
        // Strip 'on' prefix if present (e.g. 'onclick' -> 'click')
        const evt = event.startsWith('on') ? event.slice(2) : event
        node.addEventListener(evt, () => {
          if (typeof globalThis.mbt_trigger === 'function') {
            globalThis.mbt_trigger(cb_id)
          } else {
            console.warn("mbt_trigger not ready", cb_id)
          }
        })
      }
    },
    apply: (cmds) => {
      for (const cmd of cmds) {
        switch (cmd.$tag) {
          case 0: bridge.create(cmd._0, cmd._1); break
          case 1: bridge.text(cmd._0, cmd._1); break
          case 2: bridge.attr(cmd._0, cmd._1, cmd._2); break
          case 3: bridge.append(cmd._0, cmd._1); break
          case 4: bridge.updateText(cmd._0, cmd._1); break
          case 5: bridge.updateAttr(cmd._0, cmd._1, cmd._2); break
          case 6: bridge.remove(cmd._0); break
          case 7: bridge.listen(cmd._0, cmd._1, cmd._2); break
        }
      }
    },
    apply_batch: (cmds) => {
      console.log("Bridge Sync Batch:", cmds.length);
      bridge.apply(cmds)
    },
    connect_to_core: (url = 'ws://localhost:8080') => {
      console.log("Connecting to MetaEditor Core at", url);
      const ws = new WebSocket(url);
      ws.onmessage = (event) => {
        try {
          // 假设 Core 发送的是序列化后的 DomCmd 数组
          const data = JSON.parse(event.data);
          if (Array.isArray(data)) {
            bridge.apply_batch(data);
          }
        } catch (e) {
          console.error("Failed to parse remote command:", e);
        }
      };
      ws.onopen = () => console.log("Connected to Core.");
      ws.onclose = () => console.log("Disconnected from Core.");
      
      // 保存 ws 引用以便后续发送事件
      bridge.ws = ws;
    },
    // 更新 listen，使其能够将事件发回远程 Core
    listen: (id, event, cb_id) => {
      const node = nodes.get(id)
      if (node) {
        const evt = event.startsWith('on') ? event.slice(2) : event
        node.addEventListener(evt, () => {
          if (bridge.ws && bridge.ws.readyState === WebSocket.OPEN) {
            bridge.ws.send(JSON.stringify({ type: "event", callback_id: cb_id }));
          } else if (typeof globalThis.mbt_trigger === 'function') {
            globalThis.mbt_trigger(cb_id)
          }
        })
      }
    },
  }

  globalThis.mbt_bridge = bridge
  console.log("Bridge (Remote-Ready) is ready.");
})()

