pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import TestSupport
import "../.." as Plugin

// The real AdminView with the real Service: editing customers and projects.
TestCase {
  id: test
  name: "Admin"
  when: windowShown
  width: 900
  height: 900

  readonly property string dataPath: "/home/test/.local/share/on-the-clock/hours.json"

  QtObject {
    id: fakePanel
    property color fg: "#dddddd"
    property color dim: "#999999"
    property color faint: "#666666"
    property color accent: "#7fbbb3"
    property color urgent: "#e67e80"
    property string font: "monospace"
    signal scrolled()
    function focusGrid() {}
  }

  Component { id: serviceComponent; Plugin.Service {} }
  Component { id: adminComponent; Plugin.AdminView { width: 860 } }

  property var service: null
  property var admin: null

  function saved() { return JSON.parse(Fs.read(dataPath)) }
  function type(text) { for (const c of text) keyClick(c) }

  function fieldWithValue(item, value) {
    for (const c of item.children) {
      if (c.value === value && typeof c.commit === "function") return c
      const f = fieldWithValue(c, value)
      if (f) return f
    }
    return null
  }

  function cleanup() { admin.destroy(); service.destroy(); wait(50) }

  function init() {
    Fs.reset()
    Fs.write(dataPath, JSON.stringify({
      rates: [{ id: "r1", name: "Dev", amount: 100 }],
      customers: [{ id: "c1", name: "Acme", archived: false }],
      projects: [
        { id: "p1", customerId: "c1", name: "Beta", rateId: "r1", billable: true, archived: false },
        { id: "p2", customerId: "c1", name: "Gamma", rateId: "r1", billable: true, archived: false }
      ],
      entries: {}, settings: {}
    }))
    service = createTemporaryObject(serviceComponent, test)
    tryVerify(() => service.loaded)
    admin = createTemporaryObject(adminComponent, test, { service: service, panel: fakePanel })
    verify(admin)
  }

  function addProject() {
    service.addItem("projects", { id: "p9", customerId: "c1", name: "New project", rateId: "r1", billable: true, archived: false })
    admin.editingProject = "p9"
    const field = fieldWithValue(admin, "New project")
    verify(field, "name field")
    field.forceActiveFocus()
    field.selectAll()
    return field
  }

  // Renaming never moves a project: the order is yours, not by name.
  function test_renamingAProjectKeepsTheKeyboard() {
    const field = addProject()
    type("Alpha")
    tryVerify(() => saved().projects.find(p => p.id === "p9").name === "Alpha", 5000, "saved while typing")
    verify(field.activeFocus, "focus after save")
    type(" one")
    tryVerify(() => saved().projects.find(p => p.id === "p9").name === "Alpha one", 5000, "saved again")
    admin.editingProject = ""
    compare(admin.projectsOf("c1").map(p => p.name), ["Beta", "Gamma", "Alpha one"])
  }

  function test_projectsMoveUpAndDown() {
    admin.moveBy("projects", admin.projectsOf("c1"), "p2", -1)
    compare(admin.projectsOf("c1").map(p => p.name), ["Gamma", "Beta"])
    compare(saved().projects.map(p => p.id), ["p2", "p1"])
    verify(!admin.canMove(admin.projectsOf("c1"), "p2", -1), "first can't go up")
    admin.moveBy("projects", admin.projectsOf("c1"), "p2", 1)
    compare(admin.projectsOf("c1").map(p => p.name), ["Beta", "Gamma"])
  }

  // Dropping a dragged row takes the place of the row it's dropped on.
  function test_dropTakesTheTargetsPlace() {
    service.addItem("projects", { id: "p3", customerId: "c1", name: "Delta", rateId: "r1", billable: true, archived: false })
    admin.moveTo("projects", admin.projectsOf("c1"), "p3", "p1")
    compare(admin.projectsOf("c1").map(p => p.name), ["Delta", "Beta", "Gamma"])
    admin.moveTo("projects", admin.projectsOf("c1"), "p3", "p2")
    compare(admin.projectsOf("c1").map(p => p.name), ["Beta", "Gamma", "Delta"])
  }

  function test_archivedStayLast() {
    service.updateItem("projects", "p1", { archived: true })
    admin.showArchived = true
    compare(admin.projectsOf("c1").map(p => p.name), ["Gamma", "Beta"])
    verify(!admin.canMove(admin.projectsOf("c1"), "p2", 1), "not below an archived project")
    admin.moveTo("projects", admin.projectsOf("c1"), "p2", "p1")
    compare(admin.projectsOf("c1").map(p => p.name), ["Gamma", "Beta"])
  }

  // If a row comes to show another project while you type (here: the
  // project you're naming is moved), what you typed is dropped rather than
  // saved on that other project.
  function test_typingIsNeverSavedOnAnotherProject() {
    const field = addProject()
    type("Alpha")
    service.moveItem("projects", "p9", "p1", false)   // this row now shows Gamma
    compare(field.value, "Gamma")
    field.focus = false
    compare(saved().projects.map(p => p.name), ["New project", "Beta", "Gamma"])
  }
}
