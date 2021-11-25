using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class generator : MonoBehaviour
{

    public Material[] m_material;
    public int m_w;
    public int m_h;
    public bool m_randomMesh;
    public bool m_sameMaterial;
    public bool m_castShadows = true;
    public bool m_receiveShadows = true;

    private Vector3[] m_pos;
    private GameObject[] m_objs;
    private float m_clock;

    // Start is called before the first frame update
    void Start()
    {
        int total = m_w * m_h;

        m_pos = new Vector3[total];
        m_objs = new GameObject[total];

        int id = 0;
        for (int y=0;y<m_h;y++)
        {
            for (int x = 0; x < m_w; x++)
            {
                int mat = Random.Range(0, m_material.Length);

                PrimitiveType t = PrimitiveType.Cube;
                if ( m_randomMesh )
                {
                    switch (Random.Range(0, 4))
                    {
                        case 0: t = PrimitiveType.Sphere; break;
                        case 1: t = PrimitiveType.Capsule; break;
                        case 2: t = PrimitiveType.Cylinder; break;
                        case 3: t = PrimitiveType.Cube; break;
                    }
                }
                m_objs[id] = GameObject.CreatePrimitive(t);

                Collider collider = m_objs[id].GetComponent<Collider>();
                DestroyImmediate(collider);

                m_pos[id] = new Vector3(x - (float)m_w * 0.5f, 0, y - (float)m_h * 0.5f);
                m_objs[id].transform.position = m_pos[id];
                Renderer rend = m_objs[id].GetComponent<Renderer>();

                rend.lightProbeUsage = UnityEngine.Rendering.LightProbeUsage.Off;
                rend.reflectionProbeUsage = UnityEngine.Rendering.ReflectionProbeUsage.Off;

                rend.shadowCastingMode = m_castShadows ? UnityEngine.Rendering.ShadowCastingMode.On : UnityEngine.Rendering.ShadowCastingMode.Off;
                rend.receiveShadows = m_receiveShadows;

                if (m_sameMaterial)
                {
                    rend.material = m_material[0];
                }
                else
                {
                    rend.material = new Material(m_material[mat]);
                    Color col = Color.HSVToRGB(((float)(id * 10) / (float)total) % 1.0f, 0.7f, 1.0f);
                    //                Color col = Color.HSVToRGB(Random.Range(0.0f,1.0f), 1.0f, 1.0f);
                    rend.material.SetColor("_Color", col);              // set for LW
                    rend.material.SetColor("_BaseColor", col);          // set for HD
                }

                id++;
            }
        }
    }

    // Update is called once per frame
    void Update()
    {

        m_clock += Time.fixedDeltaTime;

        float t0 = m_clock * 2.0f;

        int id = 0;
        for (int y = 0; y < m_h; y++)
        {
            float t1 = t0;
            for (int x = 0; x < m_w; x++)
            {
                Vector3 pos = m_pos[id] + new Vector3(0, Mathf.Sin(t1), 0);
                m_objs[id].transform.position = pos;
                t1 += 0.373f;
                id++;
            }
            t0 += 0.25f;
        }
    }
}
