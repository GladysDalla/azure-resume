const functionAPI = "<Function_URL>";
async function getVisitCount() {
    try {
        const response = await fetch(functionAPI);
        const data = await response.json();
        document.getElementById("counter").innerText = data.count;
    } catch (error) {
        console.error("Error fetching visitor count:", error);
    }
}
window.addEventListener('DOMContentLoaded', getVisitCount);
