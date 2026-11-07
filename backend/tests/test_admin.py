"""Admin endpoints for the question bank."""

import httpx

KEY = {"X-Admin-Key": "admin-test-key"}


async def test_admin_flow(start_server):
    url = await start_server(admin_key="admin-test-key")
    async with httpx.AsyncClient(base_url=url) as http:
        assert (await http.get("/admin/questions/stats")).status_code == 401
        assert (
            await http.get("/admin/questions/stats", headers={"X-Admin-Key": "wrong"})
        ).status_code == 401
        stats = (await http.get("/admin/questions/stats", headers=KEY)).json()
        assert stats["total"] >= 300

        items = [
            {
                "type": "mcq",
                "category": "علوم",
                "text_ar": "سؤال مستورد؟",
                "options_ar": ["أ", "ب", "ج", "د"],
                "correct_index": 1,
            },
            {"type": "numeric", "category": "علوم", "text_ar": "ناقص"},
        ]
        r = await http.post(
            "/admin/questions/import?pack=sy-g9-science&license=CC-BY-SA-4.0",
            json=items,
            headers=KEY,
        )
        assert r.status_code == 200
        body = r.json()
        assert body["inserted"] == 1 and len(body["errors"]) == 1

        csv_text = (
            "type,category,difficulty,text_ar,option_1,option_2,option_3,option_4,correct_index,numeric_answer,unit_ar,source\n"
            "numeric,تاريخ,2,سؤال من ملف؟,,,,,,1453,م,ملف\n"
        )
        files = {"file": ("pack.csv", csv_text.encode("utf-8"), "text/csv")}
        r = await http.post(
            "/admin/questions/import-file?pack=sy-g9-science", files=files, headers=KEY
        )
        assert r.json()["inserted"] == 1

        listed = (await http.get("/admin/questions?pack=sy-g9-science", headers=KEY)).json()
        assert listed["total"] == 2
        qid = listed["items"][0]["id"]
        assert listed["items"][0]["license"] == "CC-BY-SA-4.0"

        r = await http.patch(
            f"/admin/questions/{qid}", json={"reviewed": True, "difficulty": 3}, headers=KEY
        )
        assert r.status_code == 200 and r.json()["reviewed"] is True
        r = await http.patch(
            f"/admin/questions/{qid}", json={"options_ar": ["أ", "أ", "ج", "د"]}, headers=KEY
        )
        assert r.status_code == 422
        assert (await http.delete(f"/admin/questions/{qid}", headers=KEY)).status_code == 204
        assert (await http.get("/admin/questions?pack=sy-g9-science", headers=KEY)).json()[
            "total"
        ] == 1
