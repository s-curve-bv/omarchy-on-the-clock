pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import "../.." as Plugin

// The plugin's dropdown: a click chooses the row under the pointer, even
// when the pointer never moved over the list (Omarchy's own Dropdown then
// chose the highlighted row, and a call was booked on the wrong project).
TestCase {
  id: test
  name: "PickList"
  when: windowShown
  width: 600
  height: 600

  Component {
    id: pickComponent
    Plugin.PickList {
      width: 400
      showLabel: false
      options: [{ value: "p1", label: "Intern" }, { value: "p2", label: "LSP" },
                { value: "p3", label: "Kring" }, { value: "p4", label: "Node" }]
      value: "p1"
    }
  }

  function optionList(o) {
    if (!o) return null
    if (o.model !== undefined && typeof o.indexOfValue === "function") return o
    for (const c of (o.data || [])) { const f = optionList(c); if (f) return f }
    return o.contentItem ? optionList(o.contentItem) : null
  }

  function test_aClickChoosesTheRowClicked() {
    const pick = createTemporaryObject(pickComponent, test)
    const chosen = []
    pick.changed.connect(v => chosen.push(v))
    pick.open()
    tryVerify(() => pick.popupOpen)
    const list = optionList(pick)
    compare(list.currentIndex, 0, "the current value is highlighted")
    const row = list.itemAtIndex(3)
    mouseClick(row, row.width / 2, row.height / 2)
    compare(chosen, ["p4"])
    verify(!pick.popupOpen)
  }

  // The owner's binding survives a pick: the call prompt's picker kept
  // showing the last call's project while booking on the new call's one.
  QtObject { id: owner; property string projectId: "p1" }
  Component {
    id: boundComponent
    Plugin.PickList {
      width: 400
      showLabel: false
      options: [{ value: "p1", label: "Intern" }, { value: "p2", label: "LSP" },
                { value: "p3", label: "Kring" }, { value: "p4", label: "Node" }]
      value: owner.projectId
      onChanged: function(v) { owner.projectId = v }
    }
  }

  function test_aPickKeepsTheValueBound() {
    owner.projectId = "p1"
    const pick = createTemporaryObject(boundComponent, test)
    pick.open()
    tryVerify(() => pick.popupOpen)
    const row = optionList(pick).itemAtIndex(3)
    mouseClick(row, row.width / 2, row.height / 2)
    compare(owner.projectId, "p4")
    compare(pick.value, "p4")
    owner.projectId = "p2"
    compare(pick.value, "p2", "the next call's project shows")
    compare(pick.currentLabel(), "LSP")
  }
}
